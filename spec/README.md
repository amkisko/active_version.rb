# Running Tests

## Using RSpec (default: Polyrun parallel)

The full suite matches CI: **parallel OS processes** via **`./bin/polyrun`** (or **`bundle exec polyrun parallel-rspec`**) — see [POLYRUN.md](../POLYRUN.md). **`polyrun.yml`** **`partition.paths_build`** refreshes **`spec/spec_paths.txt`** before **`plan`** / **`run-shards`**; to regenerate only that file: **`./bin/polyrun build-paths`**.

```bash
# Run all tests (parallel + merged coverage)
./bin/polyrun
# or: ./bin/polyrun parallel-rspec --workers 5
```

For **focused** runs (single file, line number, or `--fail-fast`), use **serial** **`bin/rspec`** (plain RSpec; no polyrun fan-out):

```bash
# Run with fail-fast (stop on first failure)
bin/rspec --fail-fast

# For verbose output
DEBUG=1 bin/rspec

# Run single spec file at exact line number
DEBUG=1 bin/rspec spec/active_version/configuration_inheritance_spec.rb:21

# Run tests for a specific module
bin/rspec spec/active_version/audits/

# Run integration tests only
bin/rspec spec/integration/
```

## Test Structure

- `spec/active_version/` - Core module and class specs
  - `audits/` - Audit-related functionality tests
  - `revisions/` - Revision-related functionality tests
  - `translations/` - Translation-related functionality tests
  - `configuration_*.rb` - Configuration and inheritance tests
  - `context_system_spec.rb` - Context management tests
  - `instrumentation_spec.rb` - Instrumentation tests

- `spec/integration/` - Integration tests with real ActiveRecord models
  - `audits_spec.rb` - Full audit workflow integration tests
  - `revisions_spec.rb` - Full revision workflow integration tests
  - `translations_spec.rb` - Full translation workflow integration tests
  - `audit_callbacks_spec.rb` - Callback integration tests
  - `audit_combiner_spec.rb` - Audit combining logic integration tests

- `spec/support/` - Shared test helpers and contexts
  - `database.rb` - Database setup and teardown helpers
  - `models.rb` - Test model definitions

## RSpec Testing Guidelines

### Core Principles

- Always assume RSpec has been integrated - Never edit `rails_helper.rb` or `spec_helper.rb` or add new testing gems
- Test Behavior, Not Implementation - Verify the public contract, not internal structure
- Refactoring Resistance - Tests should survive internal refactoring without modification
- Keep test scope minimal - start with the most crucial and essential tests
- Never test features that are built into Ruby, Rails, or external gems
- Never write tests for performance unless specifically requested
- Isolate external dependencies (HTTP calls, file system, time) at architectural boundaries only

### Spec File Organization Strategies

This gem uses the "Standard" Consensus (Mirroring) approach for most specs, with some method-specific files for complex classes.

#### 1. The "Standard" Consensus (Mirroring) - Default

The default expectation. The file structure in `spec/` mirrors `lib/` exactly 1-to-1.

```
lib/
└── active_version/
    └── audits/
        └── has_audits.rb

spec/
└── active_version/
    └── audits/
        └── has_audits_spec.rb
```

Best For: Small to medium-sized classes (< 300 lines, < 10 methods)

Why it's consensus: Zero cognitive load. If you see `lib/active_version/audits/has_audits.rb`, tests are in `spec/active_version/audits/has_audits_spec.rb`.

#### 2. The "Split Specs" Approach (Method-as-File) - For Complex Classes

For complex classes where a single file becomes unmanageable. Create a directory named after the class/module, and files named after methods (or behaviors).

```
lib/
└── active_version/
    └── audits/
        └── has_audits.rb      # Complex class with many methods

spec/
└── active_version/
    └── audits/
        └── has_audits/        # Directory matches the class name
            ├── audited_options_spec.rb
            ├── with_audited_options_spec.rb
            └── class_audited_options_spec.rb
```

Best For: Complex core classes (> 500 lines, > 10 methods, high cyclomatic complexity)

Pros:
- Focus: Only load context for the specific method you're fixing
- Git History: Easier to see changes to specific method logic
- Navigation: Quick to find tests for a specific method

Cons:
- Discovery: New contributors might look for `has_audits_spec.rb` and get confused
- Shared Contexts: May duplicate setup code across files (mitigate with `spec/support/shared_contexts`)

Key Requirement: Ensure the class is loaded in a main spec file or shared context.

#### Decision Matrix

| If your class is... | Use Approach... |
| :--- | :--- |
| Standard (under 300 lines, < 10 methods) | #1 Mirroring (Stick to this until it hurts) |
| A "God Class" (complex core, > 500 lines) | #2 Split Specs (Method-as-File) |

### Core Philosophy: Behavior Verification vs. Implementation Coupling

The fundamental principle of refactoring-resistant testing is the distinction between what a system does (Behavior) and how it does it (Implementation).

- Behavior: Defined by the Public Contract—the inputs accepted by the System Under Test (SUT) and the observable outputs or side effects it produces at its architectural boundaries.
- Implementation: Encompasses internal control flow, private helper methods, auxiliary data structures, and the specific sequence of internal operations.

> Principle: True refactoring resistance is achieved only when the test suite is agnostic to the SUT's internal composition.

When a test couples itself to implementation details—for instance, by asserting that a specific private method was called or by mocking an internal helper—it violates encapsulation. Such tests verify that the code *looks* a certain way, not that it *works*. This leads to "False Negatives" or "Fragile Tests," where a test fails simply because a developer renamed a private method or optimized a loop, even though the business logic remains correct.

### Practical Metrics and Heuristics

#### The "Danger Zone" Metrics (When to Split)

These are the practical thresholds where files become hard to read/maintain, triggering a refactor or the split approach.

| Metric | Code (lib/) | Specs (spec/) | Notes |
| :--- | :--- | :--- | :--- |
| Lines per File | 100 - 300 | 300 - 500 | At 500+ lines, a spec file becomes a "scroll nightmare." At 1,000+, it's a "God Object." |
| Lines per Method/Example | 5 - 10 | 10 - 20 | `it` blocks should be short. If an `it` block is >15 lines, you're testing too many things or setup is complex. |
| Methods per Class | ~10 - 20 | N/A | For specs, this translates to "Examples per Describe block." |

#### Strict OOP Rules

These rules are strict but excellent for the code you're writing (not necessarily the tests).

- 100 lines per class
- 5 lines per method
- 4 parameters maximum per method

How this applies: If you follow this for your `lib/` code, your classes will naturally be small, which usually means your `spec/` files (Mirroring approach) stay small automatically. Your need for splitting specs often indicates your `lib/` classes are large/complex.

#### The RuboCop Defaults (Automated Consensus)

RuboCop is the standard linter. Its defaults represent the "average" agreement of the community.

- ClassLength: Max 100 lines (often bumped to 150-200 in real apps)
- ModuleLength: Max 100 lines
- MethodLength: Max 10 lines
- RSpec/ExampleLength: Max 5 lines (statements inside the `it` block). Note: This excludes setup code like `let` or `before`.

#### Practical RSpec Heuristics

The "Scroll Test"
- If you have to scroll more than 2 screens to find the `let` definitions that apply to the test you're reading, the file is too long or the context is too nested.

The "Context Depth"
- Ideal: 2-3 levels of nesting (`describe` -> `context` -> `it`)
- Max: 4 levels
- Too Deep: 5+ levels. This usually implies you're testing logic variations that should be extracted into a separate class or method.

For Method-as-File Approach (Split Specs):
- Lines per File: Aim for < 100 lines per method-spec file. If a single method needs 200+ lines of testing, that specific method is likely too complex (Cyclomatic Complexity).
- Shared Contexts: Keep your `shared_context` files under 50 lines. If your setup is larger than that, your object graph is likely too coupled.

### Test Type Selection

#### Unit Specs (`spec/active_version/`)

- Use for: Library classes, modules, service objects, utility methods
- Test: Public API behavior, error handling, edge cases
- Example: Testing `HasAudits.audited_options`, `Configuration.inheritance`, `ColumnMapper.map`

#### Integration Specs (`spec/integration/`)

- Use for: Full workflows with real ActiveRecord models
- Test: End-to-end behavior, callback chains, database interactions
- Example: Testing complete audit creation workflow, revision snapshot creation

### Testing Workflow

1. Plan First: Think carefully about what tests should be written for the given scope/feature
2. Review Existing Tests: Check existing specs before creating new test data
3. Isolate Dependencies: Use mocks/stubs for external services (HTTP, file system, time)
4. Minimal Scope: Start with essential tests, add edge cases only when specifically requested
5. DRY Principles: Review `spec/support/` for existing shared examples and helpers before duplicating code

### The Mocking Policy: Architectural Boundaries Only

To enforce refactoring resistance, strict controls must be placed on the use of Test Doubles (mocks, stubs, spies).

#### 🚫 STRICTLY FORBIDDEN: Internal Mocks

The policy unequivocally prohibits the mocking of internals. This prohibition covers:

1. Mocking Private/Protected Methods:
   - Attempts to mock private methods are fundamentally flawed
   - These methods exist solely to organize code; they do not represent a contract
   - If a test mocks a private method, it is coupled to the signature of that method

2. Partial Mocks (Spies on the SUT):
   - Creating a real instance of the SUT but overriding one of its methods
   - This creates a "Frankenstein" object that exists only in the test environment

3. Reflection-Based State Manipulation:
   - Using reflection to set private fields to bypass validation logic
   - This tests a state that might be unreachable in the actual application

#### ✅ PERMITTED MOCKS: Architectural Boundaries

Mocking is reserved exclusively for Architectural Boundaries—the seams where the SUT interacts with systems it does not own or control.

| Boundary Type | Examples | Rationale for Mocking | Preferred Double |
| :--- | :--- | :--- | :--- |
| Persistence Layer | ActiveRecord, Database | Eliminates dependency on running DB; speed/isolation | Fake (In-Memory) or Stub |
| External I/O | HTTP Clients, RPC | Prevents network calls; simulates error states | Mock or Stub |
| File System | Disk Access | Decouples tests from slow/stateful disk | Fake (Virtual FS) |
| System Env | Time, Randomness | Removes non-determinism | Stub (Fixed Clock) |
| Eventing | Kafka, RabbitMQ | Verifies side effects without running broker | Spy (Capture events) |

### The Input Derivation Protocol

When tempted to mock an internal method to "force" code execution, STOP. Instead, use the Input Derivation Protocol.

#### Protocol Mechanics

Treat the SUT as a logic puzzle. To execute a specific line of code, solve the logical equation defined by the control flow graph leading to it.

1. Analyze the Logic (Path Predicate Analysis):
   - Examine the conditional checks (`if`, `guard clauses`)
   - *Example:* `if user.age > 18: ...`

2. Reverse Engineer the Input:
   - Determine the initial state that satisfies the predicate
   - *Result:* Input user must have `age >= 19`

3. Construct Data (The Fixture):
   - Create a data fixture that naturally satisfies the conditions
   ```ruby
   valid_user = User.new(age: 25, status: 'ACTIVE')
   ```

4. Execute via Public API:
   - Pass the constructed input into the public entry point

#### Addressing "Unreachable" Code

If the Input Derivation Protocol fails (no public input can trigger the line), the target code is technically unreachable or dead code, or it represents a defensive check for a state the system prevents elsewhere.

#### Techniques

- Basis Path Testing: Calculate cyclomatic complexity to determine the number of independent paths needed
- Equivalence Partitioning: Divide input space into partitions (e.g., Valid vs. Invalid) and test representative values
- Boundary Value Analysis: Test edges of partitions (e.g., age 17, 18, 19)

### Test Data Management

#### Test Doubles and Mocks

- Use verifying doubles (`instance_double`, `class_double`) for external dependencies only
- Create test data inline for simple cases
- Use factories or builders for complex test data when needed
- Never mock methods within the class you're testing

#### Let/Let! Usage

- `let`: Lazy evaluation - only creates when accessed; use by default
- `let!`: Eager evaluation - creates immediately; use when laziness causes issues
- Keep `let` blocks close to where they're used
- Avoid creating unused data with `let!`

#### Optional: TestProf / AnyFixture

This project does not currently use [TestProf](https://test-prof.evilmartians.io/) or [AnyFixture](https://test-prof.evilmartians.io/docs/recipes/any_fixture). If you want to speed up specs by reusing a "snapshot" of data (e.g. complex setup once per suite), you can add TestProf and use AnyFixture:

```ruby
# Gemfile
gem "test-prof", group: :test

# spec/support/fixtures.rb
TestProf::AnyFixture.register(:complex_setup) do
  # Create shared state once (e.g. Post with revisions/audits)
end

# In a spec
before { TestProf::AnyFixture.get(:complex_setup) }
```

#### Test Data for ActiveVersion

Since this is a Rails gem, test data typically:
- Uses `spec/support/models.rb` for test model definitions (Post, PostAudit, etc.)
- Uses `spec/support/database.rb` for database setup/teardown
- Creates ActiveRecord models inline for simple cases
- Uses shared contexts for complex model setups

Example:

```ruby
RSpec.describe ActiveVersion::Audits::HasAudits do
  let(:post) { Post.create!(title: "Test", body: "Body") }

  it "creates audit on update" do
    post.update!(title: "Updated")
    expect(post.audits.count).to eq(1)
  end
end
```

### Shared Contexts and Helpers

- Use `spec/support/` for shared examples, custom matchers, and test helpers
- Create shared contexts for truly shared behavior across multiple spec files
- Scope helpers appropriately using `config.include` by spec type

For Split Specs Approach:
- Shared Contexts: When using method-as-file approach, create shared contexts to avoid duplicating setup code
- Keep shared contexts small: Under 50 lines per shared context file
- Example structure:
  ```ruby
  # spec/support/shared_contexts/audit_helpers.rb
  RSpec.shared_context "audit helpers" do
    let(:post) { Post.create!(title: "Test", body: "Body") }
    let(:user) { User.create!(name: "Test User") }
    # ... shared setup
  end

  # spec/active_version/audits/has_audits/audited_options_spec.rb
  RSpec.describe ActiveVersion::Audits::HasAudits, "#audited_options" do
    include_context "audit helpers"
    # ... tests
  end
  ```

### Isolation Best Practices

#### When to Isolate

- Expensive or flaky external IO (HTTP, file system) → stub or use WebMock
- Rare/error branches hard to trigger → stub to reach them
- Nondeterminism (random, time, UUIDs) → stub to deterministic values
- Performance in tight unit scopes → replace heavy collaborators
- Database operations in unit tests → use in-memory database or stubs

#### When NOT to Isolate

- Simple Ruby operations
- Cheap internal collaborations
- Where integration tests provide clearer coverage
- ActiveRecord model operations (use real database in integration tests)

#### Isolation Techniques

- Verifying Doubles: Prefer `instance_double(Class)`, `class_double` over plain `double` to catch interface mismatches
- Stubs: `allow(obj).to receive(:method).and_return(value)` for replacing behavior
- Spies: `expect(obj).to have_received(:method).with(args)` for verifying side effects
- Time Stubs: Use `travel_to` or `Timecop` for deterministic time-dependent tests
- Sequential Returns: `and_return(value1, value2)` for modeling retries and fallbacks

#### Isolation Rules

1. Preserve Public Behavior: Test via public API, never test private methods directly
2. Mock Only Boundaries: Only mock external dependencies (HTTP, DB, File System, Time), never internal methods
3. Scope Narrowly: Keep stubs local to examples; avoid global state and `allow_any_instance_of`
4. Use Verifying Doubles: Prefer `instance_double`, `class_double` over plain doubles
5. Assert Outcomes: Focus on behavior, not internal call choreography
6. Input Derivation: When you need to test a specific code path, derive the input that naturally triggers it

### Testing ActiveRecord Models

When testing ActiveRecord-related functionality:

```ruby
RSpec.describe ActiveVersion::Audits::HasAudits do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
  end

  it "creates audit on model update" do
    post = Post.create!(title: "Test")
    post.update!(title: "Updated")
    
    expect(post.audits.count).to eq(1)
    expect(post.audits.last.audited_changes).to have_key("title")
  end
end
```

### Testing Thread-Local Configuration

When testing thread-local storage (like `with_audited_options`):

```ruby
RSpec.describe ActiveVersion::Audits::HasAudits do
  before do
    # Clear thread-local storage between tests
    Thread.current["active_version_Post_audited_options"] = nil
  end

  it "merges thread-local options with class-level options" do
    Post.with_audited_options(only: ["title"]) do
      expect(Post.audited_options[:only]).to include("title")
    end
  end
end
```

### Testing Error Handling

Always test error cases:

```ruby
it "raises error when required option is missing" do
  expect {
    Post.has_audits(invalid_option: true)
  }.to raise_error(ActiveVersion::ConfigurationError, /Invalid option/)
end
```

### Code Examples: Anti-Patterns vs. Best Practices

#### 🔴 Bad Practice: Targeted Mocking (Internal Mocks)

Why it is bad: It couples the test to `class_audited_options`. If renamed, the test crashes. The test accepts invalid input because of the mock, creating a false positive.

```ruby
# ❌ DO NOT DO THIS
RSpec.describe ActiveVersion::Audits::HasAudits, "#audited_options" do
  it "merges thread-local options" do
    # VIOLATION: Mocking a method inside the SUT
    allow(Post).to receive(:class_audited_options).and_return({only: []})
    
    Post.with_audited_options(only: ["title"]) do
      result = Post.audited_options
      expect(result[:only]).to include("title")
    end
  end
end
```

#### 🟢 Best Practice: Input Driven

Why it is good: It treats the class as a black box. It proves the logic works with valid input.

```ruby
# ✅ DO THIS
RSpec.describe ActiveVersion::Audits::HasAudits, "#audited_options" do
  it "merges thread-local options with class-level options" do
    # 1. Setup SUT with real configuration
    # Post already has has_audits configured in spec/support/models.rb
    
    # 2. Input Derivation: Use with_audited_options (public API)
    Post.with_audited_options(only: ["title"]) do
      # 3. Execution via Public API
      result = Post.audited_options
      
      # 4. Assert Behavior
      expect(result[:only]).to include("title")
    end
  end
end
```

#### 🟢 Best Practice: Boundary Mocking (External Dependencies)

Why it is good: Time is an architectural boundary. We control it via dependency injection or stubs.

```ruby
# ✅ DO THIS
RSpec.describe ActiveVersion::Revisions::HasRevisions do
  it "creates revision with correct timestamp" do
    # 1. Control 'now' via Boundary Stub
    travel_to Time.zone.parse("2024-01-01 12:00:00") do
      post = Post.create!(title: "Test")
      revision = post.revisions.first
      
      # 2. Assert Behavior: timestamp is correct
      expect(revision.created_at).to eq(Time.zone.parse("2024-01-01 12:00:00"))
    end
  end
end
```

### Anti-Patterns to Avoid

- Mocking Internal Methods: Never mock private/protected methods or methods within the class you're testing
- Partial Mocks: Never create partial mocks of the SUT (e.g., `allow(service).to receive(:internal_method)`)
- Testing Implementation Details: Don't assert that specific private methods were called
- Reflection-Based Manipulation: Don't use reflection to set private fields
- Not Isolating Boundaries: Always isolate external dependencies (HTTP, file system, time)
- Using Real External Services: Never use real external services in tests
- Testing Ruby/Gem Functionality: Don't test features built into Ruby, Rails, or external gems
- Over-Testing Edge Cases: Only test edge cases when specifically requested
- Creating Unnecessary Data: Avoid creating unused test data with `let!`
- Using `allow_any_instance_of`: Prefer proper dependency injection and stubbing

### Self-Correction Checklist

Before committing, perform this audit:

1. Ownership Check: Am I mocking a method that belongs to the class I am testing? (If YES → Delete mock)
2. Verification Target: Am I testing that the code works, or how the code works?
3. Input Integrity: Did I create the necessary input data to reach the code path naturally?
4. Refactoring Resilience: If I rename private helper methods, will this test still pass?
5. Boundary Check: Is the mock representing a true I/O boundary (DB, Web, Time)?
6. Public API: Am I testing through the public interface only?

### Example Test Structure

```ruby
RSpec.describe ActiveVersion::Audits::HasAudits do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    Thread.current["active_version_Post_audited_options"] = nil
  end

  describe "#audited_options" do
    context "with thread-local configuration" do
      it "merges thread-local options with class-level options" do
        # ✅ Test via public API
        Post.with_audited_options(only: ["title"]) do
          result = Post.audited_options
          
          # ✅ Assert behavior (what it returns), not implementation
          expect(result[:only]).to include("title")
        end
      end
    end
  end
end
```

### Summary: The Refactoring-Resistant Testing Matrix

| Feature | Strict Mocking (Recommended) | Targeted Mocking (Prohibited) |
| :--- | :--- | :--- |
| Primary Focus | Public Contract / Behavior | Internal Implementation |
| Private Methods | Ignored (Opaque Box) | Mocked / Spied / Tested Directly |
| Refactoring Safety | High (Implementation agnostic) | Low (Coupled to structure) |
| Bug Detection | High (Verifies logic integration) | Mixed (Misses integration issues) |
| Maintenance Cost | Low (Survives changes) | High (Requires updates on refactor) |
| Architectural Impact | Encourages Decoupling & DI | Encourages Tightly Coupled Code |

### Code Quality Metrics Summary

#### Target Metrics for This Gem

| Metric | Target | Warning | Critical |
| :--- | :--- | :--- | :--- |
| Spec file length | < 100 lines | 100-300 lines | > 300 lines |
| Example (`it`) length | < 10 lines | 10-20 lines | > 20 lines |
| Context nesting depth | 2-3 levels | 4 levels | 5+ levels |
| Shared context length | < 50 lines | 50-100 lines | > 100 lines |
| Methods per class (lib/) | < 10 | 10-20 | > 20 |
| Lines per class (lib/) | < 100 | 100-300 | > 300 |

#### When to Refactor

- Split a spec file when it exceeds 300 lines or requires scrolling > 2 screens to find relevant `let` definitions
- Extract shared context when setup code is duplicated across 3+ spec files
- Split a class when it exceeds 300 lines or has > 20 methods (applies to `lib/` code)
- Simplify a test when an `it` block exceeds 15 lines or tests multiple behaviors

### Coverage Goals

- Aim for comprehensive coverage of public APIs
- Test edge cases (empty strings, nil values, special characters)
- Test error conditions and boundary cases
- Focus on behavior that matters to users of the gem
- Minimum line coverage: see `config/polyrun_coverage.yml` (Polyrun `Coverage::Collector`; not SimpleCov)

### Database Testing

ActiveVersion uses `spec/support/database.rb` for database setup:

```ruby
# spec/support/database.rb provides:
# - DatabaseHelper.setup - Creates test database and tables
# - DatabaseHelper.teardown - Cleans up test database
# - Automatic schema loading for test models
```

Always use `DatabaseHelper.setup` in `before(:all)` blocks for integration tests that require database access.

### Thread-Local Storage Testing

ActiveVersion uses thread-local storage for configuration. Always clear thread-local state between tests:

```ruby
before do
  Thread.current["active_version_Post_audited_options"] = nil
end
```

### References

- [RSpec Documentation](https://rspec.info/)
- [Better Specs](https://www.betterspecs.org/)
- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)

