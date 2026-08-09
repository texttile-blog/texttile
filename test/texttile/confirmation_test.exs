defmodule Texttile.ConfirmationTest do
  use Texttile.DataCase

  alias Texttile.Comments.Address
  alias Texttile.Confirmation
  alias Texttile.Newsletter.Subscriber
  alias Texttile.Repo

  describe "the address itself" do
    test "an address is folded to one spelling" do
      assert Confirmation.normalize("  Reader@Example.ORG ") == "reader@example.org"
      assert Confirmation.normalize(nil) == ""
    end

    test "what can be an address at all" do
      assert Confirmation.address?("reader@example.org")
      refute Confirmation.address?("nope")
      refute Confirmation.address?("")
      refute Confirmation.address?("two words@example.org")
    end

    test "every token is its own" do
      refute Confirmation.token() == Confirmation.token()
    end
  end

  # The same flow under both tables: an address that commented and an
  # address on the newsletter list have different lives, and prove
  # themselves the same way.
  for {name, module, table} <- [
        {"a commenting address", Address, "comment_addresses"},
        {"a newsletter address", Subscriber, "newsletter_subscribers"}
      ] do
    describe "#{name}" do
      setup do
        row = Repo.insert!(unquote(module).build("reader-#{System.unique_integer()}@example.org"))
        %{row: row, table: unquote(table)}
      end

      test "starts unconfirmed and carries a token", %{row: row} do
        refute Confirmation.confirmed?(row)
        assert byte_size(row.token) > 16
      end

      test "the link goes out once, and again an hour later", %{row: row} do
        now = DateTime.utc_now(:second)
        me = self()
        deliver = fn token -> send(me, {:mailed, token}) end

        row = Confirmation.ask(row, deliver, now)
        assert_received {:mailed, _token}

        # inside the hour: the same link, no second mail
        row = Confirmation.ask(row, deliver, DateTime.add(now, 3599, :second))
        refute_received {:mailed, _token}

        # past it: a lost mail is no dead end
        Confirmation.ask(row, deliver, DateTime.add(now, 3601, :second))
        assert_received {:mailed, _token}
      end

      test "confirming twice changes nothing the second time", %{row: row} do
        now = DateTime.utc_now(:second)

        confirmed = Confirmation.confirm(row, now)
        assert Confirmation.confirmed?(confirmed)
        assert confirmed.confirmed_at == now

        again = Confirmation.confirm(confirmed, DateTime.add(now, 60, :second))
        assert again.confirmed_at == now
      end
    end
  end
end
