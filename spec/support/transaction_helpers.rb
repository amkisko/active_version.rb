module TransactionHelpers
  def current_transaction_id
    connection = ActiveVersion::Runtime.adapter.base_connection
    return unless ActiveVersion::Runtime.supports_current_transaction_id?(connection)

    connection.execute("SELECT pg_current_xact_id()").first&.first
  rescue *ActiveVersion::Runtime.active_record_connection_errors
    nil
  end
end

RSpec.configure do |config|
  config.include(TransactionHelpers)
end
