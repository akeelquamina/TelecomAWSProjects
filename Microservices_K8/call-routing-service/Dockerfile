# Dockerfile for Call Routing Service
FROM python:3.9

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY call_routing_service.py .

CMD ["python", "call_routing_service.py"]
