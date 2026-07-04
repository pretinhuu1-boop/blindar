# FIXTURE VULNERAVEL — datetime naive.
from datetime import datetime


def touch_login(user):
    user.last_login_at = datetime.utcnow()
    return user
