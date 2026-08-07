defmodule Texttile.Comments.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Texttile.Comments.RateLimiter

  test "three comments a minute pass, the fourth waits, another caller is free" do
    name = :"rate_limiter_#{System.unique_integer([:positive])}"
    start_supervised!({RateLimiter, name: name})

    assert RateLimiter.allow?("1.2.3.4", name)
    assert RateLimiter.allow?("1.2.3.4", name)
    assert RateLimiter.allow?("1.2.3.4", name)
    refute RateLimiter.allow?("1.2.3.4", name)
    refute RateLimiter.allow?("1.2.3.4", name)

    assert RateLimiter.allow?("5.6.7.8", name)
  end

  test "reset forgets every window" do
    name = :"rate_limiter_#{System.unique_integer([:positive])}"
    start_supervised!({RateLimiter, name: name})

    for _ <- 1..3, do: RateLimiter.allow?("1.2.3.4", name)
    refute RateLimiter.allow?("1.2.3.4", name)

    assert :ok = RateLimiter.reset(name)
    assert RateLimiter.allow?("1.2.3.4", name)
  end
end
