GithubIssueOrganizerEngine::Engine.routes.draw do
  root "issues#index"

  resources :issues, only: [ :index ] do
    collection do
      get :github_url
      get :open_in_github
      post :timeline
    end
  end

  resource :github_identity, only: [ :show, :update ]
  resource :settings, only: [ :show, :update ]
  resources :timelines, only: [ :index, :show, :edit, :update, :destroy ] do
    delete :destroy_drafts, on: :collection
    post :edit_copy, on: :member
    patch :make_current, on: :member
    resources :items, only: [ :update ], controller: "timeline_items"
    resources :unavailabilities,
      only: [ :create, :update, :destroy ],
      controller: "timeline_unavailabilities"
  end
end
