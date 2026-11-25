#!/bin/sh
# Run the command in /src as root.
# Then give the new files (.pio, dist, sdkconfig.*) back to the owner of /src.
owner=$(stat -c %u:%g /src)
uid=${owner%%:*}

"$@"
rc=$?

find /src ! -user "$uid" -exec chown -h "$owner" {} +
exit $rc
