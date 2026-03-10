require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "is valid with required fields" do
    user = User.new(name: "Jane", email: "jane@example.com", password: "password")

    assert user.valid?
  end

  test "requires name" do
    user = User.new(email: "jane@example.com", password: "password")

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "requires unique email" do
    User.create!(name: "Jane", email: "jane@example.com", password: "password")
    duplicate = User.new(name: "John", email: "jane@example.com", password: "password")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end
end
