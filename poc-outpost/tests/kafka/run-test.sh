kubectl apply -f kafka-topics.yaml
kubectl get kafkatopic.kafka.strimzi.io -n kafka

kubectl exec -it cluster-broker-0 -c kafka -n kafka -- /bin/bash -c "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"

echo "run test producer, enter some messages and then Ctrl+D to finish"
kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic

echo "run test consumer, view messages produced by the producer and then Ctrl+D to finish"
kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.43.0-kafka-3.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server cluster-kafka-bootstrap:9092 --topic test-topic --from-beginning

