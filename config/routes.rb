# frozen_string_literal: true

Rails.application.routes.draw do
  get ':id', to: 'recipes#show', constraints: { id: /[a-z0-9-]+/ }
end
