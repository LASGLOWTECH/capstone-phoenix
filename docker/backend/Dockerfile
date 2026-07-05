FROM python:3.12-slim

WORKDIR /app
COPY app/ /app/

RUN pip install --no-cache-dir flask gunicorn psycopg2-binary

EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
