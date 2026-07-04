# FIXTURE BOA — datetime aware.
from datetime import datetime, timezone


def touch_login(user):
    user.last_login_at = datetime.now(timezone.utc)
    return user
