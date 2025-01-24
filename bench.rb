require "async"
require "async/queue"
require "benchmark"

def now_ns
  Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
end

class CpuTimeWaster
  def initialize
    gather_data
    run_linear_regression
  end

  def predict_job_size_with_cpu_ns(value)
    (value - @alpha) / @beta
  end

  def predict_cpu_ns_for_job_size(value)
    @alpha + @beta * value
  end

  private

  def gather_data
    @x_values = []
    @y_values = []
    value = 30_000
    time_taken_ns = 0
    while time_taken_ns < 10 * 1000 * 1000
      start = now_ns
      count_to(value.to_i)
      time_taken_ns = now_ns - start

      @x_values << value
      @y_values << time_taken_ns
      value *= 1.01
    end
    @samples
  end

  def run_linear_regression
    # Number of data points
    n = @x_values.length

    # Calculate means of x and y
    mean_x = @x_values.sum(0.0) / n
    mean_y = @y_values.sum(0.0) / n

    # Calculate the terms needed for the numerator and denominator of beta
    sum_xy = @x_values.zip(@y_values).map { |x, y| x * y }.sum(0.0)
    sum_xx = @x_values.map { |x| x * x }.sum(0.0)

    # Calculate slope (beta) and intercept (alpha)
    @beta = (sum_xy - n * mean_x * mean_y) / (sum_xx - n * mean_x**2)
    @alpha = mean_y - @beta * mean_x
  end
end

def count_to(value)
  x = 0
  while x < value
    x += 1
  end
end

def random_with_normal_distribution(mean, stddev)
  -> {
    u1 = rand
    u2 = rand
    z0 = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    [z0 * stddev + mean, 0].max
  }
end

def gen_schedules(
  worker_count:,
  swap_count:,
  gen_cpu_job_size:,
  gen_io_time:
)
  worker_count.times.map do |i|
    schedule = []
    swap_count.times do |j|
      schedule << gen_io_time.()
      schedule << gen_cpu_job_size.()
    end
    schedule
  end
end

def perform_schedule(schedule)
  index = 0
  length = schedule.length
  while index < length do
    sleep(schedule[index])
    count_to(schedule[index + 1])
    index += 2
  end
end

def run_fibers(schedules)
  Async do
    latch = Async::Queue.new
    workers = schedules.map do |schedule|
      Async do
        latch.pop # block until ready to measure
        perform_schedule(schedule)
      end
    end
    schedules.length.times { latch << true }
    workers.each(&:wait)
  end
end

def run_threads(schedules)
  latch = Queue.new
  threads = schedules.map do |schedule|
    Thread.new do
      latch.pop # block until ready
      perform_schedule(schedule)
    end
  end
  schedules.length.times { latch << true }
  threads.each(&:join)
end

base_work_unit_ns = 5 * 1000 * 1000
cpu_time_waster = CpuTimeWaster.new
std_dev_fraction = 0.5

trial_count = 10
thread_io_times = {}
fiber_io_times = {}

trial_count.times do |trial_number|
  puts("#{trial_number}/#{trial_count}\n")
  io_percent = 1

  trial = []
  while io_percent < 100
    io_fraction = io_percent / 100.0
    cpu_fraction = (100 - io_percent) / 100.0

    puts("\t#{io_percent}/100\n")

    schedules = gen_schedules(
      worker_count: 32,
      swap_count: 16,
      gen_cpu_job_size: -> {
        time_to_take = random_with_normal_distribution(base_work_unit_ns, base_work_unit_ns * std_dev_fraction).() * cpu_fraction
        cpu_time_waster.predict_job_size_with_cpu_ns(time_to_take).floor
      },
      gen_io_time: -> {
        random_with_normal_distribution(
          base_work_unit_ns / (1000 * 1000 * 1000).to_f,
          std_dev_fraction * base_work_unit_ns / (1000 * 1000 * 1000).to_f
        ).() * io_fraction
      }
    )

    5.times do
      thread_start = now_ns
      run_threads(schedules)
      (thread_io_times[io_percent] ||= []) << (now_ns - thread_start)
    end

    5.times do
      fiber_start = now_ns
      run_fibers(schedules)
      (fiber_io_times[io_percent] ||= []) << (now_ns - fiber_start)
    end

    io_percent += 1
  end
end

File.open("records.csv", "w") do |f|
  f.puts "strategy, io_pct, time"
  {"Threads" => thread_io_times, "Fibers" => fiber_io_times}.each do |desc, values|
    values.each do |pct, times|
      times.each do |time|
        f.puts "%s, %f, %f" % [desc, pct, time]
      end
    end
  end
end
