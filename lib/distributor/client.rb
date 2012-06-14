require "distributor"
require "distributor/connector"
require "distributor/multiplexer"
require "json"

class Distributor::Client

  def initialize(input, output=input)
    @connector   = Distributor::Connector.new
    @multiplexer = Distributor::Multiplexer.new(output)
    @handlers    = {}
    @processes   = []
    @on_close    = Hash.new([])

    # reserve a command channel
    @multiplexer.reserve(0)

    # feed data from the input channel into the multiplexer
    @connector.handle(input) do |io|
      @multiplexer.input io
    end

    @connector.on_close(input) do |io|
      @multiplexer.output 0, JSON.dump({ "command" => "close", "ch" => ch })
    end

    # handle the command channel of the multiplexer
    @connector.handle(@multiplexer.reader(0)) do |io|
      data = JSON.parse(io.readpartial(4096))

      case command = data["command"]
      when "close" then
        ch = data["ch"]
        @on_close[ch].each { |c| c.call(ch) }
      when "launch" then
        ch = data["ch"]
        @multiplexer.reserve ch
        @handlers[data["id"]].call(ch)
        @handlers.delete(data["id"])
        @processes << ch
      else
        raise "no such command: #{command}"
      end
    end
  end

  def output(ch, data)
    @multiplexer.output ch, data
  end

  def run(command, &handler)
    id = "#{Time.now.to_f}-#{rand(10000)}"
    @multiplexer.output 0, JSON.dump({ "id" => id, "command" => "run", "args" => command })
    @handlers[id] = handler
  end

  def hookup(ch, input, output)
    # handle data incoming on the multiplexer
    @connector.handle(@multiplexer.reader(ch)) do |io|
      begin
        data = io.readpartial(4096)
        # output.write "#{ch}: #{data}"
        output.write data
      rescue EOFError
        @multiplexer.output 0, JSON.dump({ "command" => "close", "ch" => ch })
      end
    end

    # handle data incoming from the input channel
    @connector.handle(input) do |io|
      begin
        data = io.readpartial(4096)
        @multiplexer.output ch, data
      rescue EOFError
        @processes.each { |ch| @multiplexer.close(ch) }
      end
    end
  end

  def on_close(ch, &blk)
    @on_close[ch] << blk
  end

  def start
    loop { @connector.listen }
  end

end
