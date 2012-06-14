#!/usr/bin/env ruby

$:.unshift File.expand_path("../../lib", __FILE__)

require "distributor/client"
require "distributor/server"

def set_buffer(enable)
  with_tty do
    if enable
      `stty icanon echo`
    else
      `stty -icanon -echo`
    end
  end
end

def with_tty(&block)
  return unless $stdin.isatty
  begin
    yield
  rescue
    # fails on windows
  end
end

def get_terminal_environment
  { "TERM" => ENV["TERM"], "COLUMNS" => `tput cols`.strip, "LINES" => `tput lines`.strip }
rescue
  { "TERM" => ENV["TERM"] }
end

if ARGV.first == "server"

  begin
    server = Distributor::Server.new($stdin.dup, $stdout.dup)
    $stdout = $stderr
    server.start
  rescue Interrupt
  end

else

  begin
    client = Distributor::Client.new(IO.popen("ruby subshell.rb server", "w+"))

    client.run("bash 2>&1") do |ch|
      client.hookup ch, $stdin, $stdout
      client.on_close(ch) do
        exit 0
      end
    end

    tcp = TCPServer.new(8000)

    Thread.new do
      loop do
        Thread.start(tcp.accept) do |tcp_client|
          client.tunnel(5000) do |ch|
            client.hookup ch, tcp_client
          end
        end
      end
    end

    set_buffer false
    client.start
  rescue Interrupt
  ensure
    set_buffer true
  end

end
