
Rails.application.routes.draw do
  ActiveAdmin.routes(self)

  root "home#index"
  post "/command_line", to: "command_line#create"

  resources :users, only: [:show, :edit, :update]

  resources :posts do
    member do
      get :translations
      patch :translations, action: :update_translations
      get :revisions
      get :audits
      post :revert_to_version
      post :switch_to_version
      get :diff
    end
  end

  resources :issues do
    member do
      get :translations
      patch :translations, action: :update_translations
      get :revisions
      get :audits
      post :revert_to_version
      post :switch_to_version
    end
  end

  resources :pull_requests do
    member do
      get :translations
      patch :translations, action: :update_translations
      get :revisions
      get :audits
      post :revert_to_version
      post :switch_to_version
    end
  end

  resources :column_posts, only: [:index, :show, :edit, :update]
  resources :composite_demo_audits, path: "composite_audits", only: [:index, :show]
  resources :source_identity_posts, path: "source_partition_demo", only: [:index, :show]
  resources :categories
end
