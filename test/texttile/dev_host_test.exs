defmodule Texttile.DevHostTest do
  use ExUnit.Case, async: true

  # `bin/dev-host` prints the address the development server hands out.
  # The tests feed it an interface list through TEXTTILE_DEV_INTERFACES,
  # so they do not depend on the network of the machine that runs them.

  @script Path.expand("../../bin/dev-host", __DIR__)

  defp dev_host(interfaces, env \\ []) do
    {output, status} =
      System.cmd(@script, [], env: [{"TEXTTILE_DEV_INTERFACES", interfaces} | env])

    assert status == 0
    String.trim(output)
  end

  test "DEV_HOST answers instead of the search" do
    assert dev_host("wired 192.168.1.20", [{"DEV_HOST", "localhost"}]) == "localhost"
  end

  test "the wired address wins over Wi-Fi" do
    assert dev_host("wireless 10.0.0.5\nwired 192.168.1.20") == "192.168.1.20"
  end

  test "Wi-Fi answers when no cable is plugged in" do
    assert dev_host("wireless 10.0.0.5") == "10.0.0.5"
  end

  test "a link-local address counts as no address" do
    assert dev_host("wired 169.254.7.7\nwireless 10.0.0.5") == "10.0.0.5"
  end

  test "without any address the answer is the loopback" do
    assert dev_host("wired\nwireless") == "127.0.0.1"
  end

  test "the machine that runs the tests gets a usable address" do
    {output, 0} = System.cmd(@script, [])

    assert String.trim(output) =~ ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
  end
end
