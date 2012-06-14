require "distributor"
require "stringio"

class Distributor::Packet

  PROTOCOL_VERSION = 1

  def self.write(io, channel, data)
    io.write "DIST"
    io.write pack(PROTOCOL_VERSION)
    io.write pack(channel)
    io.write pack(data.length)
    io.write data
  end

  def self.parse(io)
    header = io.read(4)
    return if header.nil?
    raise "invalid header" unless header == "DIST"
    version = unpack(io.read(4))
    channel = unpack(io.read(4))
    length  = unpack(io.read(4))
    data    = io.read(length)

    [ channel, data ]
  end

  def self.pack(num)
    [num].pack("N")
  end

  def self.unpack(string)
    string.unpack("N").first
  end

end
