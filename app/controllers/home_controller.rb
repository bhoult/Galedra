class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    @constitution = Governance::Constitution.new
  end
end
