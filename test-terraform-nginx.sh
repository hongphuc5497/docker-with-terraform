PORT=8080
for i in {1..10}; do
  curl http://localhost:${PORT};
  sleep 1;
  echo ""
done
