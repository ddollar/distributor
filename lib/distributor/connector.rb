require "distributor"

class Distributor::Connector

  attr_reader :connections

  def initialize
    @connections = {}
    @on_close = Hash.new([])
  end

  def handle(from, &handler)
    @connections[from] = handler
  end

  def on_close(from, &handler)
    @on_close[from] << handler
  end

  def listen
    rs, ws = IO.select(@connections.keys)
    rs.each do |from|
      begin
        @on_close.each { |c| c.call(from) } if from.eof?
        self.connections[from].call(from)
      rescue Errno::EIO
        @connections.delete(from)
      end
    end
  end

  def close(io)
    @connections.delete(io)
    @on_close[io].each { |c| c.call(io) }
  end

end
