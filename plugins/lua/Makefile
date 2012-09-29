
.PHONY: clean

sandbox: sandbox.c
	$(CC) $(CFLAGS) $(LDFLAGS) -lm -o sandbox sandbox.c luasrc/liblua.a

clean:
	$(RM) sandbox

