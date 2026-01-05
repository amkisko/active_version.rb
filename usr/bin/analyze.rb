#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"

# Analyzes library structure and lints for code quality issues.

class Analyze
  MAX_FILE_SIZE_KB = 20
  MAX_FILE_LINES = 500
  MAX_MODULE_LINES = 300

  def self.run(root_dir = ".")
    new(root_dir).run
  end

  def initialize(root_dir)
    @root_dir = File.expand_path(root_dir)
    @output_file = File.join(@root_dir, "tmp/analyze.log")
  end

  def run
    FileUtils.mkdir_p(File.dirname(@output_file))

    lib_files = find_lib_files
    test_files = find_test_files
    example_files = find_example_files
    migration_files = find_migration_files

    lib_analysis = analyze_files(lib_files)
    test_analysis = analyze_files(test_files)
    example_analysis = analyze_files(example_files)
    migration_analysis = analyze_files(migration_files)

    total_lib = calculate_totals(lib_analysis)
    total_test = calculate_totals(test_analysis)
    total_example = calculate_totals(example_analysis)
    total_migration = calculate_totals(migration_analysis)

    issues = []
    issues += check_file_sizes(lib_analysis, "Library")
    issues += check_file_sizes(test_analysis, "Test")
    issues += check_file_sizes(example_analysis, "Example")
    issues += check_file_sizes(migration_analysis, "Migration")
    issues += check_todos(lib_analysis, "Library")
    issues += check_todos(test_analysis, "Test")
    issues += check_todos(example_analysis, "Example")
    issues += check_todos(migration_analysis, "Migration")
    issues += check_garbage(lib_analysis, "Library")
    issues += check_garbage(test_analysis, "Test")
    issues += check_garbage(example_analysis, "Example")
    issues += check_garbage(migration_analysis, "Migration")

    output = format_report(
      lib_analysis, test_analysis, example_analysis, migration_analysis,
      total_lib, total_test, total_example, total_migration, issues
    )

    File.write(@output_file, output)

    if issues.empty?
      puts "✓ Analysis complete - no issues found"
      puts "Report written to #{@output_file}"
      exit 0
    else
      puts "✗ Analysis found #{issues.length} issue(s):"
      puts ""
      issues.each { |issue| puts "  #{issue}" }
      puts ""
      puts "Report written to #{@output_file}"
      exit 1
    end
  end

  private

  def find_lib_files
    lib_dir = File.join(@root_dir, "lib")
    find_ruby_files(lib_dir)
  end

  def find_test_files
    test_dir = File.join(@root_dir, "spec")
    test_dir = File.join(@root_dir, "test") unless Dir.exist?(test_dir)
    find_ruby_files(test_dir)
  end

  def find_example_files
    example_dir = File.join(@root_dir, "examples")
    find_ruby_files(example_dir)
  end

  def find_migration_files
    migration_dir = File.join(@root_dir, "db/migrate")
    find_ruby_files(migration_dir)
  end

  def find_ruby_files(dir)
    return [] unless Dir.exist?(dir)

    ruby_files = Dir.glob(File.join(dir, "**/*.rb"))
      .reject { |f| f.include?("/_build/") }
      .reject { |f| f.include?("/deps/") }
      .reject { |f| f.include?("/tmp/") }
      .reject { |f| f.include?("/coverage/") }
      .sort
  end

  def analyze_files(files)
    files.map do |file|
      content = File.read(file, encoding: "UTF-8")
      lines = content.lines.length
      size = content.bytesize

      # Get relative path from project root
      relative_path = if file.start_with?(@root_dir)
        file[@root_dir.length + 1..]
      else
        file
      end

      {
        path: file,
        relative_path: relative_path,
        lines: lines,
        size: size,
        size_kb: (size / 1024.0).round(2),
        content: content
      }
    end
  end

  def calculate_totals(analysis)
    total_size = analysis.sum { |f| f[:size] }
    {
      file_count: analysis.length,
      total_lines: analysis.sum { |f| f[:lines] },
      total_size: total_size,
      total_size_kb: (total_size / 1024.0).round(2)
    }
  end

  def check_file_sizes(analysis, category)
    issues = []

    analysis.each do |file|
      if file[:size_kb] > MAX_FILE_SIZE_KB
        issues << "ERROR: #{category} file #{file[:relative_path]} exceeds size limit (#{file[:size_kb]} KB > #{MAX_FILE_SIZE_KB} KB)"
      end

      if file[:lines] > MAX_FILE_LINES
        issues << "ERROR: #{category} file #{file[:relative_path]} exceeds line limit (#{file[:lines]} lines > #{MAX_FILE_LINES} lines)"
      end

      if file[:lines] > MAX_MODULE_LINES
        issues << "WARNING: #{category} file #{file[:relative_path]} exceeds recommended module size (#{file[:lines]} lines > #{MAX_MODULE_LINES} lines)"
      end
    end

    issues
  end

  def check_todos(analysis, category)
    todo_patterns = [
      [/\bTODO\b/i, "TODO"],
      [/\bFIXME\b/i, "FIXME"],
      [/\bXXX\b/i, "XXX"],
      [/\bHACK\b/i, "HACK"],
      [/\bNOTE\b/i, "NOTE"],
      [/\bBUG\b/i, "BUG"],
      [/\bOPTIMIZE\b/i, "OPTIMIZE"],
      [/\bREFACTOR\b/i, "REFACTOR"]
    ]

    issues = []

    analysis.each do |file|
      lines = file[:content].lines

      lines.each_with_index do |line, index|
        line_num = index + 1
        # Handle encoding issues by converting to UTF-8
        line_utf8 = line.encode("UTF-8", invalid: :replace, undef: :replace)
        todo_patterns.each do |pattern, name|
          if pattern.match?(line_utf8)
            issues << "WARNING: #{category} file #{file[:relative_path]}:#{line_num} contains #{name} comment"
          end
        end
      end
    end

    issues
  end

  def check_garbage(analysis, category)
    issues = []

    garbage_patterns = [
      [/puts.*debug/i, "Debug puts"],
      [/\bp\s+[a-zA-Z_]/i, "Debug p (debug code)"],
      [/\bpp\s+[a-zA-Z_]/i, "Debug pp (debug code)"],
      [/binding\.pry/i, "binding.pry (debugger)"],
      [/binding\.irb/i, "binding.irb (debugger)"],
      [/\bdebugger\b/i, "debugger call"],
      [/\bbyebug\b/i, "byebug call"],
      [/^\s*#.*\b(pry|binding|debugger|byebug)\b/i, "Debugger comment"],
      [/^\s*#.*\b(remove|delete|cleanup|garbage|unused|deprecated)\b/i, "Cleanup comment"],
      [/^\s*#.*\b(temporary|temp|tmp|hack|workaround)\b/i, "Temporary code comment"],
      [/Rails\.logger\.debug/i, "Rails.logger.debug"],
      [/logger\.debug/i, "logger.debug"]
    ]

    analysis.each do |file|
      lines = file[:content].lines

      lines.each_with_index do |line, index|
        line_num = index + 1
        # Handle encoding issues by converting to UTF-8
        line_utf8 = line.encode("UTF-8", invalid: :replace, undef: :replace)
        garbage_patterns.each do |pattern, description|
          if pattern.match?(line_utf8)
            issues << "WARNING: #{category} file #{file[:relative_path]}:#{line_num} contains #{description}"
          end
        end
      end
    end

    issues
  end

  def format_report(lib_analysis, test_analysis, example_analysis, migration_analysis,
    total_lib, total_test, total_example, total_migration, issues)
    lib_by_size = lib_analysis.sort_by { |f| -f[:size] }
    lib_by_lines = lib_analysis.sort_by { |f| -f[:lines] }
    test_by_size = test_analysis.sort_by { |f| -f[:size] }
    test_by_lines = test_analysis.sort_by { |f| -f[:lines] }
    example_by_size = example_analysis.sort_by { |f| -f[:size] }
    example_by_lines = example_analysis.sort_by { |f| -f[:lines] }
    migration_by_size = migration_analysis.sort_by { |f| -f[:size] }
    migration_by_lines = migration_analysis.sort_by { |f| -f[:lines] }

    <<~REPORT
      ================================================================================
      ActiveVersion Library Structure Analysis
      ================================================================================
      Generated: #{Time.now.utc.iso8601}

      ================================================================================
      SUMMARY
      ================================================================================

      Library Files:
        Total files: #{total_lib[:file_count]}
        Total lines: #{total_lib[:total_lines]}
        Total size: #{total_lib[:total_size_kb]} KB (#{format_bytes(total_lib[:total_size])})

      Test Files:
        Total files: #{total_test[:file_count]}
        Total lines: #{total_test[:total_lines]}
        Total size: #{total_test[:total_size_kb]} KB (#{format_bytes(total_test[:total_size])})

      Example Files:
        Total files: #{total_example[:file_count]}
        Total lines: #{total_example[:total_lines]}
        Total size: #{total_example[:total_size_kb]} KB (#{format_bytes(total_example[:total_size])})

      Migration Files:
        Total files: #{total_migration[:file_count]}
        Total lines: #{total_migration[:total_lines]}
        Total size: #{total_migration[:total_size_kb]} KB (#{format_bytes(total_migration[:total_size])})

      Grand Total:
        Total files: #{total_lib[:file_count] + total_test[:file_count] + total_example[:file_count] + total_migration[:file_count]}
        Total lines: #{total_lib[:total_lines] + total_test[:total_lines] + total_example[:total_lines] + total_migration[:total_lines]}
        Total size: #{(total_lib[:total_size_kb] + total_test[:total_size_kb] + total_example[:total_size_kb] + total_migration[:total_size_kb]).round(2)} KB (#{format_bytes(total_lib[:total_size] + total_test[:total_size] + total_example[:total_size] + total_migration[:total_size])})

      ================================================================================
      ISSUES FOUND
      ================================================================================

      #{if issues.empty?
          "No issues found."
        else
          issues.map { |issue| "  #{issue}" }.join("\n")
        end}

      ================================================================================
      LIBRARY FILES - SORTED BY SIZE (LARGEST FIRST)
      ================================================================================

      #{format_file_list(lib_by_size, :size)}

      ================================================================================
      LIBRARY FILES - SORTED BY LINES (LARGEST FIRST)
      ================================================================================

      #{format_file_list(lib_by_lines, :lines)}

      ================================================================================
      TEST FILES - SORTED BY SIZE (LARGEST FIRST)
      ================================================================================

      #{format_file_list(test_by_size, :size)}

      ================================================================================
      TEST FILES - SORTED BY LINES (LARGEST FIRST)
      ================================================================================

      #{format_file_list(test_by_lines, :lines)}

      ================================================================================
      EXAMPLE FILES - SORTED BY SIZE (LARGEST FIRST)
      ================================================================================

      #{format_file_list(example_by_size, :size)}

      ================================================================================
      EXAMPLE FILES - SORTED BY LINES (LARGEST FIRST)
      ================================================================================

      #{format_file_list(example_by_lines, :lines)}

      ================================================================================
      MIGRATION FILES - SORTED BY SIZE (LARGEST FIRST)
      ================================================================================

      #{format_file_list(migration_by_size, :size)}

      ================================================================================
      MIGRATION FILES - SORTED BY LINES (LARGEST FIRST)
      ================================================================================

      #{format_file_list(migration_by_lines, :lines)}

      ================================================================================
      LIBRARY FILES - BY MODULE STRUCTURE
      ================================================================================

      #{format_by_module_structure(lib_analysis)}

      ================================================================================
      END OF REPORT
      ================================================================================
    REPORT
  end

  def format_file_list(files, sort_by)
    files.map.with_index(1) do |file, index|
      value = (sort_by == :size) ? "#{file[:size_kb]} KB" : "#{file[:lines]} lines"
      "#{index.to_s.rjust(3)}. #{file[:relative_path].ljust(60)} | #{value.rjust(12)} | #{file[:lines]} lines | #{format_bytes(file[:size])}"
    end.join("\n")
  end

  def format_by_module_structure(analysis)
    analysis
      .group_by { |file| File.dirname(file[:relative_path]).split("/").first || "root" }
      .map do |module_name, files|
        total_lines = files.sum { |f| f[:lines] }
        total_size = files.sum { |f| f[:size] }
        {
          module: module_name,
          file_count: files.length,
          total_lines: total_lines,
          total_size: total_size
        }
      end
      .sort_by { |m| -m[:total_size] }
      .map do |m|
        "#{m[:module].ljust(30)} | #{m[:file_count].to_s.rjust(3)} files | #{m[:total_lines].to_s.rjust(6)} lines | #{format_bytes(m[:total_size])}"
      end
      .join("\n")
  end

  def format_bytes(bytes)
    if bytes < 1024
      "#{bytes} B"
    elsif bytes < 1_048_576
      "#{(bytes / 1024.0).round(2)} KB"
    else
      "#{(bytes / 1_048_576.0).round(2)} MB"
    end
  end
end

root_dir = ARGV.empty? ? "." : ARGV.first

Analyze.run(root_dir)
