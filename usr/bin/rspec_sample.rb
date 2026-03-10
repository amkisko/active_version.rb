#!/usr/bin/env ruby
require "fileutils"

# Runs RSpec tests and returns the first failure if any, otherwise returns success.
class RSpecSample
  def self.run(root_dir = ".")
    new(root_dir).run
  end

  def initialize(root_dir)
    @root_dir = File.expand_path(root_dir)
    @log_file = File.join(@root_dir, "tmp/rspec.log")
  end

  def run
    FileUtils.mkdir_p(File.dirname(@log_file))

    # Run rspec and capture output to log file
    system("cd #{@root_dir} && bundle exec rspec > #{@log_file} 2>&1")
    exit_status = $?.exitstatus

    # If RSpec exited successfully, there were no failures.
    # Exit with success and no output.
    return if exit_status == 0

    # Parse log file to find first failure
    first_failure = find_first_failure

    # If there is no explicit Failures: section or no first failure block,
    # do not output anything.
    return unless first_failure

    start_line, end_line = first_failure
    lines = File.readlines(@log_file)
    failure_block = lines[(start_line - 1)..(end_line - 1)] || []

    # Output the exact failure lines from the rspec log
    puts failure_block.join
  end

  private

  def find_first_failure
    return nil unless File.exist?(@log_file)

    lines = File.readlines(@log_file)
    failures_section_seen = false
    first_failure_start = nil
    first_failure_end = nil

    lines.each_with_index do |line, index|
      line_num = index + 1

      # Only consider failures listed under the explicit "Failures:" section.
      if line.strip == "Failures:"
        failures_section_seen = true
        next
      end

      next unless failures_section_seen

      # Find first numbered failure (e.g., "  1) ...")
      if first_failure_start.nil? && line.match?(/^\s+\d+\)\s+/)
        first_failure_start = line_num
        next
      end

      # Find the end of first failure (next numbered failure or "Finished in")
      if first_failure_start && first_failure_end.nil?
        if line.match?(/^\s+\d+\)\s+/) && line_num > first_failure_start
          # Found next failure, so previous one ends on the line before this.
          first_failure_end = line_num - 1
          break
        elsif line.match?(/^Finished in/)
          # Found end of test run; failure ends on the line before this.
          first_failure_end = line_num - 1
          break
        end
      end
    end

    # If we found a failure but no end, use the last line
    if first_failure_start && first_failure_end.nil?
      first_failure_end = lines.length
    end

    return nil unless first_failure_start

    # Return the range for just the first failure (its numbered line and
    # everything through the trailing blank line before the next failure).
    # Example: @active_version.rb/tmp/rspec.log:1056-1062
    [first_failure_start, first_failure_end]
  end
end

# Run if called directly
if __FILE__ == $PROGRAM_NAME
  root_dir = ARGV[0] || File.expand_path(File.join(__dir__, "../.."))
  RSpecSample.run(root_dir)
end
