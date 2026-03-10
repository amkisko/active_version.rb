require "rails/generators"

module ActiveVersion
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates ActiveVersion initializer and configuration file"

      def create_initializer
        template "initializer.rb.erb", "config/initializers/active_version.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
