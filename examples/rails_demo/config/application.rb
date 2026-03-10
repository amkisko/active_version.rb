
require_relative "boot"

RailsDemo::BootProfile.measure_phase("require rails/all") do
  require "rails/all"
end

RailsDemo::BootProfile.measure_phase("bundler require groups") do
  Bundler.require(*Rails.groups)
end

RailsDemo::BootProfile.install_railtie_initializer_probe
RailsDemo::BootProfile.subscribe_initializer_notifications

module RailsDemo
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = false

    # I18n configuration
    config.i18n.default_locale = :en
    config.i18n.available_locales = [:en, :fi, :sv]

    config.after_initialize do
      RailsDemo::BootProfile.print_report
    end
  end
end
