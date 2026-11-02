import os
import tempfile

_database = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DATABASE_URL"] = "sqlite:///" + _database.name
os.environ["JWT_SECRET_KEY"] = "test-secret"
os.environ["ADMIN_PASSWORD"] = "test-pass"
os.environ["ADMIN_USERNAME"] = "admin"
os.environ["CACHE_ENABLED"] = "true"
os.environ["REDIS_URL"] = "redis://fake/0"
os.environ["CACHE_TTL_SECONDS"] = "45"
