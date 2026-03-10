class CommandLineController < ApplicationController
  def create
    result = CommandLineExecutor.new(current_user: @current_user).execute(params[:command].to_s)
    status = result[:ok] ? :ok : :unprocessable_entity

    render json: result, status: status
  end
end
