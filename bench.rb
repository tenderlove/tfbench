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
      count_to(value)
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
  GC.disable
  (0..value).each { |i| i }
  GC.enable
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

#base_work_unit_ns = 5 * 1000 * 1000
base_work_unit_ns = 20 * 1000 * 1000
cpu_time_waster = CpuTimeWaster.new
std_dev_fraction = 0.5


printf "io_percent;thread_time;fiber_time\n"

progress_file = File.open("progress.txt", "wb+")

trial_count = 10
trials = []

while trials.length < trial_count
  progress_file.write("#{trials.length}/#{trial_count}\n")
  progress_file.flush
  io_percent = 0

  trial = []
  while io_percent < 10
    io_fraction = io_percent / 100.0
    cpu_fraction = (100 - io_percent) / 100.0

    progress_file.write("\t#{io_percent}/100\n")
    progress_file.flush

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

    thread_times = 5.times.map do
      thread_start = now_ns
      run_threads(schedules)
      now_ns - thread_start
    end
    avg_thread_time = thread_times.sort[thread_times.length / 2]

    fiber_times = 5.times.map do
      fiber_start = now_ns
      run_fibers(schedules)
      now_ns - fiber_start
    end
    avg_fiber_time = fiber_times.sort[fiber_times.length / 2]

    trial << [io_percent, avg_thread_time, avg_fiber_time]

    io_percent += 1
  end

  trials << trial
end

sum = trials[0].each_with_index do |_, index|
  [index, 0, 0]
end

trials.each do |trial|
  trial.each_with_index do |data, index|
    sum[index][1] += data[1]
    sum[index][2] += data[2]
  end
end

sum.each do |data|
  printf "%f;%f;%f\n", data[0], data[1] / trials.length.to_f, data[2] / trials.length.to_f
end
