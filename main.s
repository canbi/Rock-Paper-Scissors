.global _start
_start:

/**
R0		index
R11		message
*/
	
LDR R11, =WELCOME	//Welcome message
MOV R0, #0			//index
MOV R1, #39			//iteration exit condition

//BL Display
//B end

WelcomeLoop:
	BL Display
	ADD R0, R0, #1		//i = i + 1
	
	//check whether loop is finished
	CMP R0, R1
	BEQ end
	
	// TODO TIMER INTERRUPT
	DODELAY:	
		LDR R2, =400000// delay counter
		SUBLOOP:
			SUBS R2, R2, #1
			BNE SUBLOOP
	B WelcomeLoop

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
	MOV R7, #0				//initially zero, for loading Welcome characters
	MOV R8, #0				//SUM 4 digits for displaying
	MOV R9, #24				//offset for byte addressable
	MOV R10, #0				//iterator

	Loop:
		ADD R10, R10, #1		//i = i + 1

		//Read character
		LDRB R7, [R11, R0] 		//get first one in the WELCOME
		ADD R8, R8, R7, LSL R9 	//byte addressable offset
		ADD R0, R0, #1			//index = index + 1

		//check whether loop is finished
		CMP R10, #8				//We have 8 display in SSD
		BEQ Finished

		//check for first 4 digit
		SUBS R9, R9, #8			//substract 8 for byte addressable
		BLT Update				//If 4 digit is read
		B Loop

	Update:
		MOV R9, #24				//offset reset	
		STR R8, [R6, #16]		//display first 4 digit
		MOV R8, #0				//reset SUM 4 hex digit
		B Loop
	Finished:
		STR R8, [R6]			//display first 4 digit
		POP {R0, R6-R10,PC}
	
end: B end
//WELCOME: HELLO THIS IS ROCK PAPER SCISSORS GAME
WELCOME: .byte 0x76, 0x79, 0x38, 0x38, 0x5C, 0x00, 0x78, 0x76, 0x30, 0x6D,0x00, 0x30, 0x6D,0x00, 0x50, 0x5C, 0x39, 0x75, 0x00, 0x73, 0x77 ,0x73, 0x79, 0x50,0x00, 0x6D, 0x39, 0x30, 0x6D, 0x6D, 0x5C,  0x50, 0x6D,0x00, 0x3D, 0x77, 0x55, 0x79, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
.end