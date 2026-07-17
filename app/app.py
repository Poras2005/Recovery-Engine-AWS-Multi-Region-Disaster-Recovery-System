import os
import socket
import datetime
import logging
import json
import pymysql
from flask import Flask, jsonify, request

# ── Structured Logging Configuration ───────────────────────────
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'level': record.levelname,
            'message': record.getMessage(),
            'module': record.module,
        }
        if hasattr(record, 'props'):
            log_entry.update(record.props)
        return json.dumps(log_entry)

logger = logging.getLogger('dr-app')
handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

app = Flask(__name__)

# ── Global State for Failover Simulation ───────────────────────
IS_FAILED = False

@app.before_request
def check_failure_simulation():
    # Allow health checks and simulation control endpoints to bypass interceptor
    bypass_paths = ['/health', '/simulate-fail', '/simulate-recover']
    if IS_FAILED and request.path in bypass_paths:
        return
    if IS_FAILED:
        logger.warning(f"Request to {request.path} intercepted and failed due to simulation")
        return jsonify({
            'error': 'Service temporarily unavailable (DR Simulation Active)',
            'region': REGION
        }), 503


# ── Database Configuration ─────────────────────────────────────
DB_HOST = os.environ.get('DB_HOST')
DB_USER = 'admin'
DB_PASS = os.environ.get('DB_PASSWORD')
DB_NAME = 'drappdb'
REGION  = os.environ.get('AWS_REGION', 'local')

def get_db_conn():
    if not DB_HOST:
        return None
    try:
        return pymysql.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASS,
            database=DB_NAME,
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=3
        )
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return None

# ── Initialize Database Schema ─────────────────────────────────
def init_db():
    conn = get_db_conn()
    if conn:
        try:
            with conn.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS messages (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        content TEXT NOT NULL,
                        region VARCHAR(50),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
            conn.commit()
            logger.info("Database schema verified/initialized.")
        except Exception as e:
            logger.error(f"Schema initialization failed: {e}")
        finally:
            conn.close()

# Initialize only if we are the primary (or if we can)
init_db()

@app.route('/')
def home():
    db_status = "Disconnected"
    messages = []
    
    conn = get_db_conn()
    if conn:
        db_status = "Connected"
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT content, region, created_at FROM messages ORDER BY created_at DESC LIMIT 5")
                messages = cursor.fetchall()
                # Convert timestamps to strings for JSON
                for m in messages:
                    m['created_at'] = str(m['created_at'])
        except Exception as e:
            logger.error(f"Failed to fetch messages: {e}")
        finally:
            conn.close()

    return jsonify({
        'app': 'AWS DR System (Enterprise Edition)',
        'status': 'healthy' if not IS_FAILED else 'FAILING',
        'region': REGION,
        'hostname': socket.gethostname(),
        'database_status': db_status,
        'recent_messages': messages,
        'timestamp': datetime.datetime.utcnow().isoformat()
    })

@app.route('/message', methods=['POST'])
def add_message():
    content = request.json.get('content')
    if not content:
        return jsonify({'error': 'Content is required'}), 400

    conn = get_db_conn()
    if not conn:
        return jsonify({'error': 'Database unavailable'}), 503

    try:
        with conn.cursor() as cursor:
            cursor.execute("INSERT INTO messages (content, region) VALUES (%s, %s)", (content, REGION))
        conn.commit()
        logger.info(f"New message saved from {REGION}", extra={'props': {'content_length': len(content)}})
        return jsonify({'status': 'success'}), 201
    except pymysql.err.OperationalError as e:
        if e.args and e.args[0] == 1290:
            logger.error("Database is in read-only mode (read-replica). Cannot write message.")
            return jsonify({
                'error': 'Database is read-only',
                'details': 'The standby region is active, but the database replica has not been promoted to primary yet.'
            }), 503
        logger.error(f"Database operational error: {e}")
        return jsonify({'error': 'Database operational error'}), 500
    except Exception as e:
        logger.error(f"Failed to save message: {e}")
        return jsonify({'error': 'Internal server error'}), 500
    finally:
        conn.close()

@app.route('/health')
def health():
    if IS_FAILED:
        logger.warning("Health check triggered failure response")
        return jsonify({'status': 'unhealthy', 'reason': 'simulation'}), 500
    
    # Also check DB connectivity as part of deep health check
    conn = get_db_conn()
    if not conn:
        return jsonify({'status': 'degraded', 'reason': 'db_connection_failed'}), 200 # Report degraded but keep alive
    
    conn.close()
    return jsonify({'status': 'ok'}), 200

@app.route('/simulate-fail', methods=['POST'])
def simulate_fail():
    global IS_FAILED
    IS_FAILED = True
    logger.critical(f"FAILOVER SIMULATION TRIGGERED IN {REGION}")
    return jsonify({'message': f'Failure simulation started in {REGION}. Route 53 or CloudFront will detect this shortly.'})

@app.route('/simulate-recover', methods=['POST'])
def simulate_recover():
    global IS_FAILED
    IS_FAILED = False
    logger.info(f"FAILOVER SIMULATION RECOVERED IN {REGION}")
    return jsonify({'message': f'Failure simulation stopped in {REGION}. Region is healthy again.'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
