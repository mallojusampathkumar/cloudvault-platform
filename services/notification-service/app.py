# notification-service/app.py - Sends email/SMS (mocked) via RabbitMQ
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('notification-service')

app = FastAPI(title='CloudVault Notification Service')

class NotificationRequest(BaseModel):
    user_email: str
    subject: str
    body: str
    channel: str = 'email'  # email | sms

@app.get('/health')
async def health():
    return {'status': 'healthy', 'service': 'notification-service'}

@app.get('/ready')
async def ready():
    return {'ready': True}

@app.post('/notifications')
async def send_notification(req: NotificationRequest):
    # In production: publish to RabbitMQ queue, async worker consumes
    logger.info(f'[MOCK SEND] {req.channel} to {req.user_email}: {req.subject}')
    return {'status': 'queued', 'channel': req.channel, 'recipient': req.user_email}
