require "distributor"
require "distributor/connector"
require "distributor/multiplexer"
require "pty"
require "socket"

class Distributor::Server

  def initialize(input, output=input)
    @connector   = Distributor::Connector.new
    @multiplexer = Distributor::Multiplexer.new(output)

    # reserve a command channel
    @multiplexer.reserve(0)

    # feed data from the input channel into the multiplexer
    @connector.handle(input) do |io|
      @multiplexer.input io
    end

    @connector.on_close(input) do |ch|
      exit 0
    end

    # handle the command channel of the multiplexer
    @connector.handle(@multiplexer.reader(0)) do |io|
      append_json(io.readpartial(4096))

      dequeue_json do |data|
        case command = data["command"]
        when "tunnel" then
          ch = tunnel(data["port"])
          @multiplexer.output 0, JSON.dump({ "id" => data["id"], "command" => "ack", "ch" => ch })
        when "close" then
          @multiplexer.close data["ch"]
        when "run" then
          ch = run(data["args"])
          @multiplexer.output 0, JSON.dump({ "id" => data["id"], "command" => "ack", "ch" => ch })
        else
          raise "no such command: #{command}"
        end
      end
    end
  end

  def run(command)
    ch = @multiplexer.reserve

    rd, wr, pid = PTY.spawn(command)

    # handle data incoming from process
    @connector.handle(rd) do |io|
      begin
        @multiplexer.output(ch, io.readpartial(4096))
      rescue EOFError
        @multiplexer.close(ch)
        @connector.close(io)
      end
    end

    # handle data incoming on the multiplexer
    @connector.handle(@multiplexer.reader(ch)) do |input_io|
      data = input_io.readpartial(4096)
      wr.write data
    end

    ch
  end

  def tunnel(port)
    ch = @multiplexer.reserve

    tcp = TCPSocket.new("localhost", port)

    # handle data incoming from process
    @connector.handle(tcp) do |io|
      begin
        @multiplexer.output(ch, io.readpartial(4096))
      rescue EOFError
        @multiplexer.close(ch)
        @connector.close(io)
      end
    end

    # handle data incoming on the multiplexer
    @connector.handle(@multiplexer.reader(ch)) do |input_io|
      data = input_io.readpartial(4096)
      tcp.write data
    end

    ch
  end
  def start
    @multiplexer.output 0, JSON.dump({ "command" => "hello" })
    loop { @connector.listen }
  end

private

  def append_json(data)
    @json ||= ""
    @json += data
  end

  def dequeue_json
    while idx = @json.index("}")
      yield JSON.parse(@json[0..idx])
      @json = @json[idx+1..-1]
    end
  end

end
