# Non-ActiveRecord Runtime Integrations

ActiveVersion is ActiveRecord-native by default, but runtime wiring can be replaced.

Use this when your app uses Sequel (or another data layer) for connection/runtime concerns, while still using ActiveVersion models and APIs.

## Runtime adapter contract

Your runtime adapter must implement:

- `base_connection`
- `connection_for(model_class, version_type)`

Optional capability hooks:

- `supports_transactional_context?(connection)`
- `supports_current_transaction_id?(connection)`

If capability hooks are omitted, ActiveVersion falls back to adapter name detection for PostgreSQL-specific behavior.

## Minimal adapter shape

```ruby
class MyRuntimeAdapter
  def base_connection
    # connection-like object used for runtime-wide operations
  end

  def connection_for(model_class, version_type)
    # connection-like object for the source model and version type
  end
end
```

## Capabilities and database behavior

- PostgreSQL-only operations (transaction context/session keys, partition catalog checks) are guarded by capability hooks.
- SQLite/MySQL/other engines can return `false` (or omit hooks) and still work for non-PG paths.
- ActiveVersion does not enforce one database engine; it only checks capabilities before PG-specific SQL.

## Architecture boundaries

ActiveVersion owns:

- versioning/auditing/translation behavior
- callback/query helpers
- instrumentation events

Application owns:

- connection topology
- routing and replication policy
- partition lifecycle and maintenance
- runtime adapter implementation details

## Sequel-like examples

See runnable samples:

- `examples/sinatra_demo/runtime_adapter_example.rb`
- `examples/sinatra_demo/sequel_like_runtime_adapter_example.rb`
