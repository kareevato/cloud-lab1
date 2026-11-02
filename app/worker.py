import json
import logging
import os
import signal

import boto3

import cache
from database import SessionLocal, engine, ensure_schema
from models import JobModel, NoteModel

log = logging.getLogger("worker")
stop = False


def handle_term(signum, _frame):
    global stop
    stop = True
    log.info("signal %s, finish the current batch and exit", signum)


def process(body: dict) -> None:
    """Apply one queued write. Safe to run again: a finished job is not inserted twice."""
    db = SessionLocal()
    try:
        query = db.query(JobModel).filter(JobModel.id == body["job_id"])
        if engine.dialect.name != "sqlite":
            query = query.with_for_update()
        job = query.one_or_none()
        if job is None:
            log.warning("unknown job %s", body.get("job_id"))
            return
        if job.status == "done":
            log.info("duplicate delivery for job %s", job.id)
            return

        note = NoteModel(text=body["text"], author=body.get("author"))
        db.add(note)
        db.flush()
        job.status = "done"
        job.note_id = note.id
        db.commit()
        cache.invalidate(cache.NOTES_LIST_KEY, f"author:{note.author}")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    signal.signal(signal.SIGTERM, handle_term)
    signal.signal(signal.SIGINT, handle_term)
    ensure_schema()

    queue_url = os.environ["SQS_QUEUE_URL"]
    region = os.getenv("AWS_REGION", "eu-north-1")
    client = boto3.client("sqs", region_name=region)
    log.info("worker listening on %s", queue_url)

    while not stop:
        response = client.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=5,
            WaitTimeSeconds=20,
            VisibilityTimeout=60,
        )
        for message in response.get("Messages", []):
            if stop:
                return
            try:
                process(json.loads(message["Body"]))
                client.delete_message(QueueUrl=queue_url, ReceiptHandle=message["ReceiptHandle"])
            except Exception:
                log.exception("message failed, it will become visible again")


if __name__ == "__main__":
    main()
