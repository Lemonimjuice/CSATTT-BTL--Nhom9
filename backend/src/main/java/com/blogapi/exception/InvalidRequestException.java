package com.blogapi.exception;

/** A rejected client input (pagination, sorting, comment reply target...), answered with 400. */
public class InvalidRequestException extends RuntimeException {
    public InvalidRequestException(String message) { super(message); }
}
