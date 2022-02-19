;Zúñiga Salazar Vania Paola  IS-727444
;Flores Gallardo Carlos Rafael	IS-727635
;Gras Olea Alejandro	IS-726598

;************************
;Declaración de variables
;************************

LCD_E				EQU P0.0
LCD_RW				EQU P0.1
LCD_RS				EQU P0.2
LCD_DISPLAY_BUS		EQU P1
KEYBOARD_INPUT		EQU P2
DELAY_SHORT_VAR		EQU R2
DELAY_LONG_VAR		EQU R3
LCD_VAR				EQU R4
RAM_POINTER			EQU R0
TEMP_RAM_POINTER	EQU R1
ASCII_REGISTER 		EQU R5
KEYBOARD_COUNTER 	EQU R6
ALT_PIN				EQU P3.4
ALT_LED				EQU P0.3

;************************

ORG 0000H
JMP MAIN

;************************
;Vectores de interrupción
;************************

;Primer vector de interrupción (INT0)
ORG 0003H
	JMP ISR_1
	
;Segundo vector de interrupción (INT1)
ORG 0013H
	JMP ISR_2



;************************
;Rutina principal
;************************
ORG 00040H
MAIN:
	ACALL RESET_MEMORY
	ACALL INIT_LCD_DISPLAY
	ACALL INIT_INTERRUPTIONS
	ACALL INIT_SERIAL_TIMER
	
	;Este loop está haciendo un polling constante al input de ALT para ver si cambia a modo ALT. 
	;Si se activa, prende el LED de alt y cambia el valor de Keyboard Counter a 1 para que la 
	;interrupción 0 (Leer teclado) la procese en el futuro.
	main_loop:
		JNB ALT_PIN, $
		INC KEYBOARD_COUNTER
		SETB ALT_LED
		JB ALT_PIN, $
		;Ahora esperará a que Keyboard Counter sea reseteado por la interrupción 1 para 
		;volver a la normalidad y poder recibir otro input en ALT.
		CJNE KEYBOARD_COUNTER, #00H, $
		JMP main_loop
	
	
;************************


;************************
;Subrutinas
;************************



;****************************
;Interrupt Service Routine 1
;****************************
;Leer el dato del teclado matricial, guardarlo en la RAM y enviarlo a la pantalla LCD. También checa el 
;Keyboard Counter para ver si estamos en modo ALT y actúa acorde a eso.
ISR_1:
		;Si nuestro keyboard counter es 2, estamos en el modo ALT y vamos en el segundo input. El primero
		;ya se debería encontrar en LCD_VAR.
		CJNE KEYBOARD_COUNTER, #02H, isr_01
		;Sumamos el siguiente input al que teníamos anteriormente para completar el caracter ASCII y lo guardamos y enviamos.
		MOV A, LCD_VAR
		ADD A, KEYBOARD_INPUT
		MOV LCD_VAR, A
		;Reseteamos Keyboard Counter porque ya concluyó el modo ALT
		MOV KEYBOARD_COUNTER, #00H
		ACALL LCD_SEND_DATA
		CLR ALT_LED
	RETI
	
	;Si no es 2, checamos si es 1. Si lo es, entonces necesitamos guardar el input en la parte superior del acumulador.
	isr_01:	
		CJNE KEYBOARD_COUNTER, #01H, isr_normal
		;Añadimos el input, el cual mide 4 bits, al acumulador y le hacemos swap para que quede en la parte superior.
		MOV A, KEYBOARD_INPUT
		SWAP A
		;Lo guardamos en LCD_VAR para uso futuro.
		MOV LCD_VAR, A
		;Incrementamos Keyboard Counter a 2.
		INC KEYBOARD_COUNTER
	RETI
	
	;Si no es ni 1 ni 2, es un caso normal. Tomamos el input del teclado, lo volvemos un ASCII, lo guardamos y lo enviamos.
	isr_normal:
		MOV A, KEYBOARD_INPUT
		ACALL CHANGE_TO_ASCII	
		MOV LCD_VAR, A
		ACALL LCD_SEND_DATA
	
	RETI
	
;*************************


;****************************
;Interrupt Service Routine 2
;****************************
;Envía todos los datos guardados en la RAM por medio de serial.
ISR_2:
	;Recorremos todas las ubicaciones de RAM en las que guardamos los inputs
	;y las enviamos al módulo Bluetooth por medio de SEND_ACC_SERIAL.
	MOV TEMP_RAM_POINTER, #30H
	
	memory_loop:
		MOV A, @TEMP_RAM_POINTER	
		ACALL SEND_ACC_SERIAL	
		INC TEMP_RAM_POINTER
		CJNE TEMP_RAM_POINTER, #50H, memory_loop
	

	RETI
	
;*****************************

;Pone todas las variables que usaremos (incluyendo memoria RAM) en su estado default.
RESET_MEMORY:
	MOV LCD_VAR, #00H
	MOV DELAY_SHORT_VAR, #00H
	MOV DELAY_LONG_VAR, #01H
	;RAM_POINTER va en 30H porque las direcciones de RAM utilizables que usaremos
	;empiezan en 30H
	MOV RAM_POINTER, #030H
	MOV KEYBOARD_COUNTER, #00H
	;Necesitamos ALT_PIN en 1 porque necesitaremos que sirva de input.
	SETB ALT_PIN
	CLR ALT_LED
	CLR LCD_RS
	CLR LCD_RW
	CLR LCD_E
	CLR TI
	
	;Este ciclo recorrerá todas las direcciones de RAM que usaremos y las pondrá en
	;cero para que no tengamos valores basura.
	MOV TEMP_RAM_POINTER, #30H
	
	memory_reset_loop:		
		MOV @TEMP_RAM_POINTER, #00H
		INC TEMP_RAM_POINTER
		CJNE TEMP_RAM_POINTER, #50H, memory_reset_loop
		
	RET

;Borra todos los valores de la RAM del micro y hace Clear Display (Instrucción 01H) a la pantalla LCD.
RESET_RAM_AND_LCD:
	MOV TEMP_RAM_POINTER, #30H
	MOV LCD_VAR, #01H
	ACALL LCD_SEND_INSTRUCTION
	
	ACALL LCD_CHANGE_ROW_TO_1
	
	reset_ram_and_lcd_loop:	
		MOV @TEMP_RAM_POINTER, #00H
		INC TEMP_RAM_POINTER
		CJNE TEMP_RAM_POINTER, #50H, reset_ram_and_lcd_loop
		
		
	RET
	

;Inicializamos el timer 1 para que nos permita transmitir de manera serial a 9600 baudios.
INIT_SERIAL_TIMER:
	;SM0 SM1 SM2 REN TBS RBS TI RI
	MOV SCON, #01000000B
	;G T/C M1 M0 G T/C M1 M0
	MOV TMOD, #00100000B
	MOV TH1, #0FDH
	MOV TL1, #(-3)
	;Activamos el timer tras configurarlo.
	SETB TR1
	
	RET

;Inicializar display. Enviamos la instrucción 38H (Modo 16x2) tres veces con pausas de por medio,
;luego 01H (Clear display) y 0FH (Cursor activado con parpadeo)
INIT_LCD_DISPLAY:	
	;Enviamos la instrucción #38H tres veces con pausas.
	MOV LCD_VAR, #38H
	ACALL LCD_SEND_INSTRUCTION
	ACALL DELAY_LONG
	
	MOV LCD_VAR, #38H
	ACALL LCD_SEND_INSTRUCTION
	ACALL DELAY_LONG
	
	MOV LCD_VAR, #38H
	ACALL LCD_SEND_INSTRUCTION
	ACALL DELAY_LONG
	
	;Ahora enviamos la instrucción de prender el display con una pausa.
	MOV LCD_VAR, #01H
	ACALL LCD_SEND_INSTRUCTION
	ACALL DELAY_LONG	
	
	;Activamos el cursor y lo ponemos en modo parpadeo.
	MOV LCD_VAR, #0FH
	ACALL LCD_SEND_INSTRUCTION
	ACALL DELAY_LONG
	RET
	
	
;Envía a la pantalla lo que esté en LCD_VAR como un dato normal.
LCD_SEND_DATA:
	SETB LCD_RS ;RS debe estar en alto para que la pantalla interprete lo recibido como dato.
	MOV LCD_DISPLAY_BUS, LCD_VAR
	SETB LCD_E
	NOP ;Con este NOP de buffer aseguramos que se tarde los 500ns necesarios.
	CLR LCD_E
	
	;Hacemos una pausa corta para darle tiempo a la pantalla de procesar.
	ACALL DELAY_SHORT
	;Guardamos el dato enviado en la RAM para cuando tengamos que enviarlo por serial.
	ACALL STORE_LCD_VAR
	
	RET

;Envía lo que esté en LCD_VAR como una instrucción.
LCD_SEND_INSTRUCTION:
	CLR LCD_RS ;RS debe estar en bajo para que la pantalla interprete lo recibido como instrucción.
	MOV LCD_DISPLAY_BUS, LCD_VAR
	SETB LCD_E
	NOP ;Con este NOP de buffer aseguramos que se tarde los 500ns necesarios.
	CLR LCD_E	
	RET
	
;Habilita los vectores de interrupción.
INIT_INTERRUPTIONS:
	;EA-x-ET2-ES-ET1-EX1-ET0-EX0	
	MOV IE, #10000101B
	SETB IT0 ;Interrupción 0 activada por flanco de bajada.
	SETB IT1 ;Interrupción 1 activada por flanco de bajada.
	RET	
	
;Guarda lo que esté en LCD_VAR en la ubicación en donde apunta RAM_POINTER y lo avanza una ubicación.
STORE_LCD_VAR:
	MOV A, LCD_VAR
	MOV @RAM_POINTER, A
	INC RAM_POINTER
	
	;Si nuestro RAM_POINTER llegó a 40H, ya escribimos 16 datos y necesitamos cambiar el display a la segunda fila.
	CJNE RAM_POINTER, #40H, NO_CHANGE_1
	ACALL LCD_CHANGE_ROW_TO_2	
	
	NO_CHANGE_1: 	
		;Si nuestro RAM_POINTER llegó a 50H, llegó al final de la segunda fila porque ya escribimos 32 datos. Hay que reiniciarlo y mover el display a
		;la primera fila.
		CJNE RAM_POINTER, #50H, NO_CHANGE_2
		ACALL RESET_RAM_AND_LCD
		MOV RAM_POINTER, #30H
		ACALL RESET_RAM_AND_LCD
	
	NO_CHANGE_2:
 		RET


;Hace que el apuntador de la pantalla LCD vaya a la segunda fila.
LCD_CHANGE_ROW_TO_2:
	MOV LCD_VAR, #0C0H
	ACALL LCD_SEND_INSTRUCTION
	RET
	
;Hace que el apuntador de la pantalla LCD vaya a la primera fila.	
LCD_CHANGE_ROW_TO_1:
	MOV LCD_VAR, #80H
	ACALL LCD_SEND_INSTRUCTION
	RET


;Envía lo que está en el acumulador por el puerto serial y espera a que termine.
SEND_ACC_SERIAL:
	MOV SBUF, A
	JNB TI, $
	CLR TI
	RET

;Transforma un valor hexadecimal de 4 bits en el acumulador a su equivalente ASCII. El resultado lo deja en el acumulador.
CHANGE_TO_ASCII:
	MOV ASCII_REGISTER, A
	;Al principio del algoritmo tenemos el valor que convertiremos a ASCII en el acumulador. Guardamos una copia en ASCII_REGISTER.
	;Compararemos si es 0 o A. Si no lo es, entonces le iremos restando uno hasta que lo sea. 
	;Si llegó primero a A, significa que era A o mayor (A-F hexadecimal), por lo que le sumaremos 
	;el 37H necesario para volverlo el caracter ASCII correcto. Si llegó primero al 0, estaba en el rango del 0 al 9,
	;por lo que le debemos sumar 30H para acomodarlo en la tabla ASCII.
	ascii_step_0:
		CJNE A, #00H, ascii_step_1
		MOV A, ASCII_REGISTER
		ADD A, #30H
		RET
	ascii_step_1:
		CJNE A, #0AH, ascii_step_2
		MOV A, ASCII_REGISTER
		ADD A, #37H	
		RET
	ascii_step_2:
		DEC A
		SJMP ascii_step_0
	
	
	

;Espera una cantidad larga de tiempo 	
DELAY_LONG:
	MOV DELAY_LONG_VAR, #15H	

;Espera una cantidad corta de tiempo 
DELAY_SHORT:
	MOV DELAY_SHORT_VAR, #0FFH
	DJNZ DELAY_SHORT_VAR, $
	DJNZ DELAY_LONG_VAR, DELAY_SHORT
	MOV DELAY_LONG_VAR, #01H ;Le ponemos 1 para que si hacemos un Delay Short en el futuro, no vaya a decrementar a DelayLongVar a FF
	RET



	


END