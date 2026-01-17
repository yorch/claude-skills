# Code Review Checklist

A comprehensive checklist for reviewing code changes, organized by category with examples of issues and fixes.

## Correctness & Logic

### Edge Cases

- [ ] **Null/undefined handling**

  ```javascript
  // Bad: No null check
  function getName(user) {
    return user.name.toUpperCase();
  }

  // Good: Safe access
  function getName(user) {
    return user?.name?.toUpperCase() ?? 'Unknown';
  }
  ```

- [ ] **Empty collections**

  ```python
  # Bad: Crashes on empty list
  def get_first(items):
      return items[0]

  # Good: Handle empty case
  def get_first(items):
      return items[0] if items else None
  ```

- [ ] **Boundary values**

  ```go
  // Bad: Off-by-one error
  for i := 0; i <= len(items); i++ {
      process(items[i]) // Panics on last iteration
  }

  // Good: Correct boundary
  for i := 0; i < len(items); i++ {
      process(items[i])
  }
  ```

### Error Handling

- [ ] **Errors not swallowed silently**

  ```typescript
  // Bad: Silent failure
  try {
    await saveData(data);
  } catch (e) {
    // Nothing here
  }

  // Good: Proper handling
  try {
    await saveData(data);
  } catch (e) {
    logger.error('Failed to save data', { error: e, data });
    throw new DataSaveError('Unable to save data', { cause: e });
  }
  ```

- [ ] **Specific error types**

  ```python
  # Bad: Catch-all
  try:
      result = api.fetch(url)
  except Exception:
      return None

  # Good: Specific handling
  try:
      result = api.fetch(url)
  except requests.Timeout:
      logger.warning(f"Timeout fetching {url}")
      return cached_value
  except requests.HTTPError as e:
      logger.error(f"HTTP error: {e.status_code}")
      raise
  ```

### Race Conditions

- [ ] **Shared state protection**

  ```go
  // Bad: Unprotected counter
  var counter int
  func increment() {
      counter++
  }

  // Good: Thread-safe
  var counter int64
  func increment() {
      atomic.AddInt64(&counter, 1)
  }
  ```

## Security

### Input Validation

- [ ] **SQL Injection Prevention**

  ```python
  # Bad: String interpolation
  cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

  # Good: Parameterized query
  cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
  ```

- [ ] **XSS Prevention**

  ```javascript
  // Bad: Direct HTML insertion
  element.innerHTML = userInput;

  // Good: Text content or sanitization
  element.textContent = userInput;
  // or
  element.innerHTML = DOMPurify.sanitize(userInput);
  ```

- [ ] **Command Injection**

  ```python
  # Bad: Shell injection
  os.system(f"convert {filename} output.png")

  # Good: Use subprocess with list args
  subprocess.run(["convert", filename, "output.png"], check=True)
  ```

- [ ] **Path Traversal**

  ```javascript
  // Bad: Unsanitized path
  const filePath = `./uploads/${req.params.filename}`;

  // Good: Validate and sanitize
  const filename = path.basename(req.params.filename);
  const filePath = path.join(UPLOAD_DIR, filename);
  if (!filePath.startsWith(UPLOAD_DIR)) {
    throw new Error('Invalid path');
  }
  ```

### Sensitive Data

- [ ] **No secrets in code**

  ```python
  # Bad: Hardcoded secret
  API_KEY = "sk-1234567890abcdef"

  # Good: Environment variable
  API_KEY = os.environ.get("API_KEY")
  ```

- [ ] **No sensitive data in logs**

  ```javascript
  // Bad: Logging passwords
  logger.info('User login', { email, password });

  // Good: Redact sensitive fields
  logger.info('User login', { email, password: '[REDACTED]' });
  ```

- [ ] **Secure password handling**

  ```python
  # Bad: Storing plain text
  user.password = submitted_password

  # Good: Hash with salt
  user.password_hash = bcrypt.hashpw(
      submitted_password.encode(), bcrypt.gensalt()
  )
  ```

### Authentication & Authorization

- [ ] **Authorization checks present**

  ```typescript
  // Bad: No authorization
  app.delete('/users/:id', async (req, res) => {
    await User.delete(req.params.id);
  });

  // Good: Check permissions
  app.delete('/users/:id', requireAuth, async (req, res) => {
    if (req.user.id !== req.params.id && !req.user.isAdmin) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    await User.delete(req.params.id);
  });
  ```

## Best Practices

### Naming

- [ ] **Descriptive names**

  ```javascript
  // Bad: Cryptic names
  const d = new Date();
  const x = users.filter(u => u.a > 18);

  // Good: Clear intent
  const currentDate = new Date();
  const adultUsers = users.filter(user => user.age > 18);
  ```

- [ ] **Consistent conventions**

  ```python
  # Bad: Mixed styles
  def getUserData():
      user_name = "John"
      UserAge = 25

  # Good: Consistent snake_case (Python)
  def get_user_data():
      user_name = "John"
      user_age = 25
  ```

### Function Design

- [ ] **Single Responsibility**

  ```typescript
  // Bad: Does too much
  async function processOrder(order) {
    validateOrder(order);
    const total = calculateTotal(order);
    await saveToDatabase(order);
    await sendEmail(order.customer);
    await updateInventory(order.items);
    return { order, total };
  }

  // Good: Separated concerns
  async function processOrder(order) {
    validateOrder(order);
    const total = calculateTotal(order);
    await orderRepository.save(order);
    await eventBus.publish('order.created', { order, total });
    return { order, total };
  }
  ```

- [ ] **Reasonable size**

  Functions should typically be under 50 lines. If larger, consider:
  - Can it be split into helper functions?
  - Does it have multiple responsibilities?
  - Are there repeated patterns to extract?

### Error Messages

- [ ] **Helpful without exposing internals**

  ```python
  # Bad: Exposes internals
  raise Exception(f"MySQL error: {e.args[0]} on query: {sql}")

  # Good: User-friendly
  raise ValidationError("Unable to save user. Please check your input.")
  # Log the technical details separately
  logger.error("Database error", exc_info=True, extra={"sql": sql})
  ```

## DRY & Reusability

### Code Duplication

- [ ] **Extract repeated logic**

  ```javascript
  // Bad: Duplicated validation
  function createUser(data) {
    if (!data.email || !data.email.includes('@')) {
      throw new Error('Invalid email');
    }
    // ...
  }

  function updateUser(data) {
    if (!data.email || !data.email.includes('@')) {
      throw new Error('Invalid email');
    }
    // ...
  }

  // Good: Shared validation
  function validateEmail(email) {
    if (!email || !email.includes('@')) {
      throw new Error('Invalid email');
    }
  }

  function createUser(data) {
    validateEmail(data.email);
    // ...
  }
  ```

- [ ] **Configuration over repetition**

  ```python
  # Bad: Repeated structure
  STAGE_CONFIG = {"host": "stage.example.com", "debug": True}
  PROD_CONFIG = {"host": "prod.example.com", "debug": False}

  # Good: Base + overrides
  BASE_CONFIG = {"timeout": 30, "retries": 3}
  ENVIRONMENTS = {
      "stage": {**BASE_CONFIG, "host": "stage.example.com", "debug": True},
      "prod": {**BASE_CONFIG, "host": "prod.example.com", "debug": False},
  }
  ```

## Code Smells

### Magic Numbers/Strings

- [ ] **Use named constants**

  ```typescript
  // Bad: Magic numbers
  if (user.age >= 18 && user.score > 750) {
    setTimeout(retry, 3000);
  }

  // Good: Named constants
  const ADULT_AGE = 18;
  const MINIMUM_CREDIT_SCORE = 750;
  const RETRY_DELAY_MS = 3000;

  if (user.age >= ADULT_AGE && user.score > MINIMUM_CREDIT_SCORE) {
    setTimeout(retry, RETRY_DELAY_MS);
  }
  ```

### Deep Nesting

- [ ] **Max 3 levels of nesting**

  ```python
  # Bad: Deeply nested
  def process(data):
      if data:
          if data.valid:
              for item in data.items:
                  if item.active:
                      if item.value > 0:
                          do_something(item)

  # Good: Early returns and extraction
  def process(data):
      if not data or not data.valid:
          return

      for item in data.items:
          process_item(item)

  def process_item(item):
      if not item.active or item.value <= 0:
          return
      do_something(item)
  ```

### Dead Code

- [ ] **Remove unused code**

  ```javascript
  // Bad: Commented-out code
  function calculate(x) {
    // const oldResult = x * 2;
    // if (oldResult > 100) {
    //   return oldResult;
    // }
    return x * 3;
  }

  // Good: Clean code (use git for history)
  function calculate(x) {
    return x * 3;
  }
  ```

## Performance

### N+1 Queries

- [ ] **Batch database operations**

  ```python
  # Bad: N+1 queries
  users = User.query.all()
  for user in users:
      orders = Order.query.filter_by(user_id=user.id).all()  # N queries!

  # Good: Eager loading
  users = User.query.options(joinedload(User.orders)).all()
  for user in users:
      orders = user.orders  # Already loaded
  ```

### Efficient Data Structures

- [ ] **Choose appropriate structures**

  ```python
  # Bad: O(n) lookup in list
  allowed_ids = [1, 2, 3, 4, 5]
  if user_id in allowed_ids:  # O(n)
      allow()

  # Good: O(1) lookup in set
  allowed_ids = {1, 2, 3, 4, 5}
  if user_id in allowed_ids:  # O(1)
      allow()
  ```

### Resource Management

- [ ] **Properly close resources**

  ```python
  # Bad: Resource leak
  def read_file(path):
      f = open(path)
      return f.read()  # File never closed!

  # Good: Context manager
  def read_file(path):
      with open(path) as f:
          return f.read()
  ```

- [ ] **Clean up event listeners**

  ```javascript
  // Bad: Memory leak
  useEffect(() => {
    window.addEventListener('resize', handleResize);
  }, []);

  // Good: Cleanup on unmount
  useEffect(() => {
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);
  ```

## Testing

### Test Coverage

- [ ] **New features have tests**
- [ ] **Edge cases are tested**
- [ ] **Error paths are tested**

### Test Quality

- [ ] **AAA Pattern (Arrange, Act, Assert)**

  ```python
  def test_user_can_login():
      # Arrange
      user = create_user(email="test@example.com", password="secret")

      # Act
      result = login(email="test@example.com", password="secret")

      # Assert
      assert result.success is True
      assert result.user.id == user.id
  ```

- [ ] **Descriptive test names**

  ```javascript
  // Bad: Vague name
  test('user test', () => {});

  // Good: Describes behavior
  test('should return 401 when user provides invalid credentials', () => {});
  ```

- [ ] **Independent tests**

  ```python
  # Bad: Tests depend on order
  class TestUser:
      user_id = None

      def test_create(self):
          user = User.create(name="Test")
          TestUser.user_id = user.id  # Shared state!

      def test_delete(self):
          User.delete(TestUser.user_id)  # Depends on test_create

  # Good: Each test is independent
  class TestUser:
      def test_create(self):
          user = User.create(name="Test")
          assert user.id is not None

      def test_delete(self):
          user = User.create(name="Test")  # Own setup
          User.delete(user.id)
          assert User.get(user.id) is None
  ```

## Quick Reference

### Severity Guide

| Issue Type             | Severity   | Examples                              |
| ---------------------- | ---------- | ------------------------------------- |
| Security vulnerability | Critical   | SQL injection, XSS, secrets in code   |
| Data loss risk         | Critical   | Missing transactions, race conditions |
| Logic error            | Bug        | Wrong condition, off-by-one           |
| Performance issue      | Important  | N+1 queries, memory leaks             |
| Code smell             | Warning    | Deep nesting, magic numbers           |
| Style inconsistency    | Suggestion | Naming conventions, formatting        |

### Common Patterns to Flag

1. `catch (e) { }` - Empty catch blocks
2. `// TODO` - Incomplete implementations
3. `console.log` in production code
4. Hard-coded credentials or API keys
5. `any` type in TypeScript
6. Missing `await` on async functions
7. Unused imports or variables
8. Commented-out code blocks
