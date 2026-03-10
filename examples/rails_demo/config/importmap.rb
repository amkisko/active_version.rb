# Pin npm packages by running ./bin/importmap

pin "application"

pin "flowbite", to: "flowbite.js", preload: true
pin "@rails/ujs", to: "rails_ujs_esm.js", preload: true
pin "active_admin", to: "active_admin.js", preload: true

if defined?(ActiveAdmin::Engine)
  pin_all_from ActiveAdmin::Engine.root.join("app/javascript/active_admin"), under: "active_admin", preload: true
end
