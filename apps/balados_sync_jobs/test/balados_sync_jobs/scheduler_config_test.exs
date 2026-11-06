defmodule BaladosSyncJobs.SchedulerConfigTest do
  @moduledoc """
  Every configured Quantum job must be schedulable with the time zone
  database the app actually runs with. Since timex (and tzdata) were removed
  the default database is `Calendar.UTCOnlyTimeZoneDatabase`: a job declared
  with `timezone: "UTC"` raises `Quantum.DateLibrary.InvalidTimezoneError`
  and Quantum silently drops it from the schedule.
  """

  use ExUnit.Case, async: true

  alias Quantum.DateLibrary

  @configured_jobs Application.compile_env!(:balados_sync_jobs, [BaladosSyncJobs.Scheduler, :jobs])

  test "the three maintenance jobs are configured" do
    assert Keyword.keys(@configured_jobs) |> Enum.sort() ==
             [:ownership_claim_cleanup, :play_token_cleanup, :snapshot_worker]
  end

  for {name, _opts} <-
        Application.compile_env!(:balados_sync_jobs, [BaladosSyncJobs.Scheduler, :jobs]) do
    test "job #{name} has a time zone Quantum can use without tzdata" do
      job = BaladosSyncJobs.Scheduler.find_job(unquote(name))
      assert job, "job #{unquote(name)} is not registered in the scheduler"

      now = NaiveDateTime.utc_now()
      assert %NaiveDateTime{} = DateLibrary.to_tz!(now, job.timezone)
    end
  end
end
