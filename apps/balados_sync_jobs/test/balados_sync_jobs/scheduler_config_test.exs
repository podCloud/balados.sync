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

  for {name, _opts} <- @configured_jobs do
    test "job #{name} is registered and schedulable without tzdata" do
      job = BaladosSyncJobs.Scheduler.find_job(unquote(name))
      # Registration alone proves little: Quantum keeps a job with an unusable
      # zone registered and only leaves it out of the run schedule. The red
      # signal comes from the two conversions Quantum performs when scheduling.
      assert job, "job #{unquote(name)} is not registered in the scheduler"

      now = NaiveDateTime.utc_now()
      assert %NaiveDateTime{} = local = DateLibrary.to_tz!(now, job.timezone)
      assert %NaiveDateTime{} = DateLibrary.to_utc!(local, job.timezone)
    end
  end
end
