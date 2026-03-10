require "test_helper"

class CommandLineControllerTest < ActionDispatch::IntegrationTest
  test "executes command line command" do
    post command_line_path, params: { command: "help" }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "Command Help", body["title"]
  end

  test "returns unprocessable entity for invalid command" do
    post command_line_path, params: { command: "invalid xyz" }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["ok"]
    assert_equal "Command Error", body["title"]
  end
end
