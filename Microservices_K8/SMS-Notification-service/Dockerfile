# Dockerfile for SMS Notification Service
FROM python:3.9

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sms_notification_service.py .

CMD ["python", "sms_notification_service.py"]
