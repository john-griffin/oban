defmodule Oban.Engines.DolphinTest do
  use Oban.Case

  alias Oban.Engine

  @moduletag :dolphin

  describe "fetch_jobs/3" do
    test "fetching isn't blocked by an uncommitted insert into the same queue" do
      name = start_supervised_oban!(engine: Oban.Engines.Dolphin, repo: DolphinRepo)
      conf = Oban.config(name)

      {:ok, other} =
        DolphinRepo.config()
        |> Keyword.take([:hostname, :port, :username, :password, :database])
        |> MyXQL.start_link()

      # Refresh the row estimate, which drifts as sandboxed tests roll back their inserts.
      MyXQL.query!(other, "ANALYZE TABLE oban_jobs", [], query_type: :text)

      for ref <- 1..20, do: insert!(name, %{ref: ref}, queue: :alpha)

      MyXQL.query!(other, "BEGIN", [], query_type: :text)

      MyXQL.query!(other, """
      INSERT INTO oban_jobs (queue, worker, args) VALUES ('alpha', 'Oban.Integration.Worker', '{}')
      """)

      {:ok, meta} = Engine.init(conf, queue: "alpha", limit: 50)

      task = Task.async(fn -> Engine.fetch_jobs(conf, meta, %{}) end)
      result = Task.yield(task, 1_000)

      MyXQL.query!(other, "ROLLBACK", [], query_type: :text)

      assert {:ok, {:ok, {_meta, jobs}}} = result || {:blocked, Task.await(task)}
      assert 20 == length(jobs)
    end
  end
end
