package com.blogapi.exception;

/** A rejected client pagination/sorting option, before building a repository query. */
public class InvalidRequestException extends RuntimeException {
    public InvalidRequestException(String message) { super(message); }
}
