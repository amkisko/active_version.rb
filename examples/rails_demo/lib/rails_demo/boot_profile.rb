module RailsDemo
  module BootProfile
    class << self
      def enabled?
        ENV["BOOT_PROFILE"] == "1"
      end

      def measure_phase(label)
        return yield unless enabled?

        started_at
        start = now
        result = yield
        duration_ms = (now - start) * 1000.0
        phase_timings << [duration_ms, label]
        puts format_line(duration_ms, label)
        result
      end

      def install_railtie_initializer_probe
        return unless enabled?
        return if @railtie_probe_installed
        return unless defined?(Rails::Initializable::Initializer)

        Rails::Initializable::Initializer.prepend(RailtieInitializerProbe)
        @railtie_probe_installed = true
      end

      def subscribe_initializer_notifications
        return unless enabled?
        return if @initializer_subscription_installed
        return unless defined?(ActiveSupport::Notifications)

        ActiveSupport::Notifications.subscribe("load_config_initializer.railties") do |_name, start, finish, _id, payload|
          initializer = payload[:initializer].to_s
          duration_ms = (finish - start) * 1000.0
          config_initializer_timings << [duration_ms, initializer]
        end

        @initializer_subscription_installed = true
      end

      def print_report(io: $stdout, railtie_limit: 60)
        return unless enabled?

        io.puts "\n[BOOT_PROFILE] Pre-initializer phases (slowest first):"
        phase_timings.sort_by { |duration_ms, _phase| -duration_ms }.each do |duration_ms, phase|
          io.puts format_line(duration_ms, phase)
        end

        total_ms = (now - started_at) * 1000.0
        io.puts format_line(total_ms, "total boot to after_initialize")

        io.puts "\n[BOOT_PROFILE] Initializer timings (slowest first):"
        config_initializer_timings.sort_by { |duration_ms, _initializer| -duration_ms }.each do |duration_ms, initializer|
          io.puts format_line(duration_ms, initializer)
        end

        io.puts "\n[BOOT_PROFILE] Railtie initializer timings (slowest first):"
        railtie_initializer_timings.sort_by { |duration_ms, _initializer| -duration_ms }.first(railtie_limit).each do |duration_ms, initializer|
          io.puts format_line(duration_ms, initializer)
        end
      end

      def railtie_initializer_timings
        @railtie_initializer_timings ||= []
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def started_at
        @started_at ||= now
      end

      def phase_timings
        @phase_timings ||= []
      end

      def config_initializer_timings
        @config_initializer_timings ||= []
      end

      def format_line(duration_ms, label)
        format("[BOOT_PROFILE] %8.2fms  %s", duration_ms, label)
      end
    end

    module RailtieInitializerProbe
      def run(*)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        super
      ensure
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
        context_name = @context&.class&.name || self.class.name
        RailsDemo::BootProfile.railtie_initializer_timings << [duration_ms, "#{context_name}##{name}"]
      end
    end
  end
end
