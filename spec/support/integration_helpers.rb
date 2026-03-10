module IntegrationHelpers
  def cleanup_test_data
    ActiveRecord::Base.connection.execute("DELETE FROM post_audits")
    ActiveRecord::Base.connection.execute("DELETE FROM post_revisions")
    ActiveRecord::Base.connection.execute("DELETE FROM post_translations")
    ActiveRecord::Base.connection.execute("DELETE FROM posts")
  end

  def reset_active_version_context
    ActiveVersion::RequestStore.audited_user = nil
    ActiveVersion::RequestStore.request_uuid = nil
    ActiveVersion::RequestStore.remote_address = nil
    ActiveVersion.context = {}
  end

  # Re-establish revision callbacks on Post so integration specs are not broken by
  # earlier specs that call skip_callback (e.g. activerecord_compatibility_spec).
  def ensure_revision_callbacks_restored
    return unless defined?(Post)
    return unless Post.respond_to?(:revision_options) && Post.revision_options
    return unless Post.respond_to?(:setup_revision_callbacks)

    Post.setup_revision_callbacks(Post.revision_options)
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, type: :integration

  config.before(type: :integration) do
    ensure_revision_callbacks_restored
  end
end
