# Dockerfile for Billing Service
FROM python:3.9

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY billing_service.py .

CMD ["python", "billing_service.py"]
