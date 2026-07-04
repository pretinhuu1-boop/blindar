# FIXTURE BOA — worker com jobs registrados.
async def process_email(ctx, to):
    return to


class WorkerSettings:
    functions = [process_email]
    redis_settings = None
