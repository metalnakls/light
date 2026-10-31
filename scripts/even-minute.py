#!/usr/bin/env python3
"""Wait for a publication window in the user's timezone."""
from datetime import datetime
from zoneinfo import ZoneInfo
import time

while True:
    now = datetime.now(ZoneInfo("Europe/Moscow"))
    if (now.minute % 2 == 0 and now.minute not in (30, 50)
            and (now.minute != 0 or now.hour % 2 == 0 or now.hour == 1)
            and now.second <= 10):
        break
    time.sleep(1)
