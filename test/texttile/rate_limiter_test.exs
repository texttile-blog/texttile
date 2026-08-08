defmodule Texttile.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Texttile.RateLimiter

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

  test "a limiter of its own carries its own limit" do
    wide = :"rate_limiter_#{System.unique_integer([:positive])}"
    narrow = :"rate_limiter_#{System.unique_integer([:positive])}"
    start_supervised!({RateLimiter, name: wide, limit: 5})
    start_supervised!({RateLimiter, name: narrow})

    for _ <- 1..5, do: assert(RateLimiter.allow?("1.2.3.4", wide))
    refute RateLimiter.allow?("1.2.3.4", wide)

    # The same caller, the same moment: two limiters, two buckets.
    for _ <- 1..3, do: assert(RateLimiter.allow?("1.2.3.4", narrow))
    refute RateLimiter.allow?("1.2.3.4", narrow)
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
