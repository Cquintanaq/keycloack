// src/main/java/com/example/listener/RabbitMQProducer.java
package com.example.listener;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.Connection;
import com.rabbitmq.client.ConnectionFactory;

public class RabbitMQProducer {
    private final Channel channel;

    public RabbitMQProducer() throws Exception {
        ConnectionFactory factory = new ConnectionFactory();
        factory.setHost("rabbitmq"); // nombre del servicio en Docker
        factory.setPort(5672);
        factory.setUsername("keycloak_user");
        factory.setPassword("clave-segura");
        factory.setVirtualHost("/keycloak");

        Connection connection = factory.newConnection();
        this.channel = connection.createChannel();
        this.channel.queueDeclare("keycloak-user-events", true, false, false, null);
    }

    public void send(String message) throws Exception {
        this.channel.basicPublish("", "keycloak-user-events", null, message.getBytes("UTF-8"));
    }
}