.global _start
_start:

/**
R0		index
R11		message
*/
	
LDR R11, =WELCOME	//Welcome message
MOV R0, #0			//index
BL Display
B end

/**	
Display Subroutine
Displays 8 character into seven segment display
	
INPUT 1		R0	=> index
INPUT 2		R11 => Message 
*/
Display:
	//TODO PUSH
	PUSH {R0,R6-R10,LR}
	LDR R6, =0xFF200020		//Display address
	MOV R7, #0			//initially zero, for loading Welcome characters
	MOV R8, #0			//SUM 4 digits for displaying
	MOV R9, #24			//offset for byte addressable
	MOV R10, #0			//iterator

	Loop:
		ADD R10, R10, #1		//i = i + 1

		//Read character
		LDRB R7, [R11, R0] 		//get first one in the WELCOME
		ADD R8, R8, R7, LSL R9 	//byte addressable offset
		ADD R0, R0, #1			//index = index + 1

		//check whether loop is finished
		CMP R10, #8			//We have 8 display in SSD
		BEQ Finished

		//check for first 4 digit
		SUBS R9, R9, #8			//substract 8 for byte addressable
		BLT Update			//If 4 digit is read
		B Loop

	Update:
		MOV R9, #24			//offset reset	
		STR R8, [R6, #16]		//display first 4 digit
		MOV R8, #0			//reset SUM 4 hex digit
		B Loop
	Finished:
		STR R8, [R6]			//display first 4 digit
		POP {R0, R6-R10,PC}
	
end: B end
WELCOME: .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x00, 0x00
.end