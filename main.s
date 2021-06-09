.section .vectors, "ax"
	B _start 		// reset vector
	B SERVICE_UND 		// undefined instruction vector
	B SERVICE_SVC 		// software interrrupt vector
	B SERVICE_ABT_INST 	// aborted prefetch vector
	B SERVICE_ABT_DATA 	// aborted data vector
	.word 0 		// unused vector
	B SERVICE_IRQ 		// IRQ interrupt vector
	B SERVICE_FIQ 		// FIQ interrupt vector
.text
.global _start
_start:

.equ TIMER_BASE, 0xFFFEC600
.equ DISP_BASE, 0xFF200020
.equ PUSH_BASE, 0xFF200050
.equ LED_BASE, 0xFF200000
Configurations:
	//Set up stack pointers for IRQ and SVC processor modes
	MOV R1, #0b11010010 		//interrupts masked, MODE = IRQ
	MSR CPSR_c, R1 			//change to IRQ mode
	LDR SP, =0xFFFFFFFF - 3 	//set IRQ stack to A9 onchip memory

	//Change to SVC (supervisor) mode with interrupts disabled
	MOV R1, #0b11010011 		//interrupts masked, MODE = SVC
	MSR CPSR, R1 			//change to supervisor mode
	LDR SP, =0x3FFFFFFF - 3 	//set SVC stack to top of DDR3 memory
	BL CONFIG_GIC 			//configure the ARM GIC

	//PUSH BUTTON
	LDR R0, =PUSH_BASE	 	//pushbutton KEY base address
	//Initially only push button 0 is functional
	MOV R1, #0x1 			//set interrupt mask bits
	STR R1, [R0, #0x8] 		//interrupt mask register (base + 8)
	
	//TIMER
	LDR R0, =TIMER_BASE 		//Cortex-A9 Private Timer Interrupt status base address
	MOV R1, #0x1 			//set interrupt mask bit
	STR R1, [R0, #0xC]		//interrupt mask register

	//enable IRQ interrupts in the processor
	MOV R0, #0b01010011 // IRQ unmasked, MODE = SVC
	MSR CPSR_c, R0
	
	//Configure timer
	LDR R0, =TIMER_BASE 		//timer address
	LDR R1, =0x2FAF080		//50million
	STR R1, [R0] 			//Timer load value
	//Load timer controls
	MOV R1, #7 			//binary 011 to start counting
	STR R1, [R0, #8] 		//+8 -> control adress
	
	//clear registers after configuration
	MOV R0, #0
	MOV R1, #0
	
Main:
	BL StartSequence
	
	//waiting for push button 0 interrupt
	BL StartGame
	
	//GAME LOOP STARTS
	GameLoop:
		//Check FINISH
		LDR R10, =NOT_FINISH
		LDR R9, [R10]
		CMP R9, #0x0
		BEQ GameFinished 	//if finished
	
		//Check PAUSE
		LDR R10, =PLAY
		LDR R9, [R10]
		CMP R9, #0x0
		BEQ PausedMessage	//if paused
		B GameContinue		//if game continues
		
		PausedMessage:
			LDR R11, =PAUSE		//Pause message
			MOV R1, #1			//iteration exit condition
			BL Message
		
		Paused: //Pause Idle Loop
			LDR R10, =PLAY
			LDR R9, [R10]
			CMP R9, #0x0
			BEQ Paused

		GameContinue:
			//Display "Choose R1 P2 S3" message
			LDR R11, =CHOOSE		//Choose message
			MOV R1, #1			//iteration exit condition
			BL Message	
		
			//check whether the round is played
			LDR R10, =TURN_PLAYED
			LDR R9, [R10]
			CMP R9, #0
			BEQ GameLoop
			
			//If the round is played, then Show Results
			BL ShowResults
			
			//Check game is finished or not
			BL CheckScores
			
			B GameLoop
	
	GameFinished:
		BL FinishAndStart
		B Main


/*******************************************
Finish and Start game  Subroutine
Best of 5 control
*/
FinishAndStart:
	PUSH {R1,R2,R9-R11,LR}
	LDR R11, =END		//End message
	MOV R1, #1			//iteration exit condition
	BL Message
	//waits 3 seconds
	MOV R2, #3
	BL Sleep
	
	//Update Flags as initial values
	MOV R10, #0
	LDR R9, =PLAY
	STR R10, [R9]
	LDR R9, =USER_SCORE
	STR R10, [R9]
	LDR R9, =COMP_SCORE
	STR R10, [R9]
	
	MOV R10, #1
	LDR R9, =NOT_FINISH
	STR R10, [R9]
	
	//PUSH BUTTON configuration
	LDR R0, =PUSH_BASE	 	//pushbutton KEY base address
	//Initially only push button 0 is functional
	MOV R1, #0x1 			//set interrupt mask bits
	STR R1, [R0, #0x8] 		//interrupt mask register (base + 8)
	
	POP {R1,R2,R9-R11,PC}

/*******************************************
Check Results  Subroutine
Best of 5 control
*/
CheckScores:
	PUSH {R9-R10,LR}
	LDR R9, =USER_SCORE
	LDR R10, [R9]
	CMP R10, #3
	BEQ UpdateFinishedFlag
	
	LDR R9, =COMP_SCORE
	LDR R10, [R9]
	CMP R10, #3
	BEQ UpdateFinishedFlag
	B DoneCheckScores
	
	UpdateFinishedFlag:
		LDR R9, =NOT_FINISH
		MOV R10, #0
		STR R10, [R9]
	DoneCheckScores:
		POP {R9,R10,PC}
	
/*******************************************
Show Result Subroutine
*/
ShowResults:
	PUSH {R1,R2,R9-R11,LR}
	
	//Acknowledge the TURN_PLAYED
	LDR R10, =TURN_PLAYED
	MOV R11, #0
	STR R11, [R10]

	//Display who chose what
	LDR R11, =YOU_VS_COMP
	MOV R1, #1			//iteration exit condition
	BL Message
	//waits 1 seconds
	MOV R2, #1
	BL Sleep

	BL DisplayUserChoice
	BL DisplayCompChoice
	//waits 2 seconds
	MOV R2, #2
	BL Sleep

	//DRAW -> 0
	//COMP -> 1
	//USER -> 2
	LDR R10, =RESULT
	LDR R9, [R10]
	CMP R9, #1
	BEQ CompWonResult
	CMP R9, #2
	BEQ UserWonResult

	//Display DRAW
	DrawResult:			//DRAW -> 0
		LDR R11, =DRAW
		MOV R1, #1			//iteration exit condition
		BL Message			
		B ResultWait
	
	//Display COMP WON
	CompWonResult:		//COMP -> 1
		//update score
		LDR R11, =COMP_SCORE
		LDR R1, [R11]
		ADD R1,R1,#1
		STR R1, [R11]
		
		LDR R11, =COMP_WON
		MOV R1, #1			//iteration exit condition
		BL Message			
		B ResultWait
	
	//Display USER WON
	UserWonResult:		//USER -> 2
		//update score
		LDR R11, =USER_SCORE
		LDR R1, [R11]
		ADD R1,R1,#1
		STR R1, [R11]
		
		LDR R11, =YOU_WON
		MOV R1, #1			//iteration exit condition
		BL Message			

	ResultWait:
		//waits 3 seconds
		MOV R2, #3
		BL Sleep
		
		//Show Scores
		BL DisplayUserScore
		BL DisplayCompScore
		//waits 2 seconds
		MOV R2, #2
		BL Sleep
		
	POP {R1,R2,R9-R11,PC}

/*******************************************
Start Game Subroutine
Starts the game, Play flag is now 1
All the push buttons are functional
*/
StartGame:
	PUSH {R10,R11,LR}
	//Play control
	PlayControl:
		LDR R10, =PLAY
		LDR R11, [R10]
		CMP R11, #0x0
		BEQ PlayControl	
	
	//All push buttons are now functional
	LDR R10, =PUSH_BASE	 	//pushbutton KEY base address
	MOV R11, #0xF 			//set interrupt mask bits
	STR R11, [R10, #0x8] 		//interrupt mask register (base + 8)
	POP {R10,R11,PC}

/*******************************************
Start Sequence Subroutine
Displays start messages
*/
StartSequence:
	PUSH {R1,R2,R11,LR}
	LDR R11, =ANIMATION		//Animation
	MOV R1, #1			//iteration exit condition
	BL Message
	
	//waits 1 seconds
	MOV R2, #2
	BL Sleep
	
	LDR R11, =WELCOME		//Welcome message
	MOV R1, #47			//iteration exit condition
	BL Message
	
	//waits 1 seconds
	MOV R2, #1
	BL Sleep
	
	LDR R11, =ROCK			//Rock message
	MOV R1, #1			//iteration exit condition
	BL Message
	
	//waits 3 seconds
	MOV R2, #3
	BL Sleep
	
	LDR R11, =PAPER			//Paper message
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =SCISSORS		//Scissors message
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =BUTTONS		//Buttons message
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =PLAY_PAUSE_BUTTON	//Play or pause button message
	MOV R1, #17			//iteration exit condition
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =ROCK_BUTTON		//Rock button message
	MOV R1, #1			//iteration exit condition
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =PAPER_BUTTON		//Paper button message
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =SCISSORS_BUTTON	//Scissors button message
	BL Message
	
	BL Sleep			//waits 3 seconds
	LDR R11, =START			//Start message
	BL Message
	
	POP {R1,R2,R11,PC}

/*******************************************
Message Subroutine
Displays messages in seven segment display
Starting index always 0
	
INPUT 1		R1	=> iteration exit condition
INPUT 2		R11 => Message 
*/
Message:
	PUSH {R0,R5-R10,LR}
	MOV R0, #0			//index

	MessageLoop:
		//Tımer control
		Control:
			LDR R10, =TIMER
			LDR R9, [R10]
			CMP R9, #0x0
			BEQ Control

		//Set TIMER 0 again
		MOV R9, #0
		STR R9, [R10]
		BL Display
		ADD R0, R0, #1		//i = i + 1

		//check whether loop is finished
		CMP R0, R1
		BEQ DoneMessage
		B MessageLoop
	DoneMessage:
		POP {R0, R5-R10,PC}
		

/*******************************************
Display Subroutine
Displays 8 character into seven segment display
	
INPUT 1		R0	=> index
INPUT 2		R11 => Message 
*/
Display:
	PUSH {R0,R6-R10,LR}
	LDR R6, =DISP_BASE		//Display address
	MOV R7, #0			//initially zero, for loading Message characters
	MOV R8, #0			//SUM 4 digits for displaying
	MOV R9, #24			//offset for byte addressable
	MOV R10, #0			//iterator

	Loop:
		ADD R10, R10, #1		//i = i + 1
		//Read character
		LDRB R7, [R11, R0] 		//get first one in the Message
		ADD R8, R8, R7, LSL R9 		//byte addressable offset
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
		STR R8, [R6]			//display last 4 digit
		POP {R0, R6-R10,PC}

/*******************************************
Display User Choice Subroutine
*/
DisplayUserChoice:
	PUSH {R6-R10,LR}
	LDR R6, =DISP_BASE	//Display address
	LDR R7, =0x1C		//Character V
	
	LDR R9, =ICONS
	LDR R8, =USER_CHOICE
	LDR R10, [R8]
	LDRB R8, [R9, R10] 		//User Choice 
	
	LSL R8, #16
	ADD R8,R8,R7
	STR R8, [R6, #16]		//display first 4 digit
	POP {R6-R10,PC}

/*******************************************
Display Comp Choice Subroutine
*/
DisplayCompChoice:
	PUSH {R6-R10,LR}
	LDR R6, =DISP_BASE	//Display address
	LDR R7, =0x6D000000		//Character V
	
	LDR R9, =ICONS
	LDR R8, =COMP_CHOICE
	LDR R10, [R8]
	LDRB R8, [R9, R10] 		//COMP Choice 
	
	LSL R8, #8
	ADD R8,R8,R7
	STR R8, [R6]		//display last 4 digit
	POP {R6-R10,PC}

/*******************************************
Display User Result Subroutine
*/
DisplayUserScore:
	PUSH {R6-R10,LR}
	LDR R6, =DISP_BASE	//Display address
	LDR R7, =0x1C		//Character V
	
	LDR R9, =NUMBERS
	LDR R8, =USER_SCORE
	LDR R10, [R8]
	LDRB R8, [R9, R10] 		//User Choice 
	
	LSL R8, #16
	ADD R8,R8,R7
	STR R8, [R6, #16]		//display first 4 digit
	POP {R6-R10,PC}

/*******************************************
Display Comp Result Subroutine
*/
DisplayCompScore:
	PUSH {R6-R10,LR}
	LDR R6, =DISP_BASE	//Display address
	LDR R7, =0x6D000000		//Character V
	
	LDR R9, =NUMBERS
	LDR R8, =COMP_SCORE
	LDR R10, [R8]
	LDRB R8, [R9, R10] 		//COMP Choice 
	
	LSL R8, #8
	ADD R8,R8,R7
	STR R8, [R6]		//display last 4 digit
	POP {R6-R10,PC}

/*******************************************
Sleep Subroutine
Displays messages in seven segment display
Starting index always 0
	
INPUT 1		R2	=> second
*/
Sleep:
	PUSH {R2,R3, R9-R10, LR}
	LSL R2, #2		//Multiply with 4 for get seconds
	MOV R3, #0		//iteration
	SleepLoop:
		ControlSleep:
			LDR R10, =TIMER
			LDR R9, [R10]
			CMP R9, #0x0
			BEQ ControlSleep
		
		//Set TIMER 0 again
		MOV R9, #0
		STR R9, [R10]
		
		ADD R3, R3, #1		//i = i + 1
		CMP R3, R2 		//compare with given seconds value
		BEQ	DoneSleep
		B SleepLoop
	DoneSleep:
		POP {R2,R3, R9-R10, PC}
		
/* Define the exception service routines */
/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
	B SERVICE_UND
/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
	B SERVICE_SVC
/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
	B SERVICE_ABT_DATA
/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
	B SERVICE_ABT_INST

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
	PUSH {R0-R7, LR}
	/* Read the ICCIAR from the CPU Interface */
	LDR R4, =0xFFFEC100
	LDR R5, [R4, #0x0C] 	//read from ICCIAR
	
FPGA_IRQ1_HANDLER:
	//Timer control
	CMP R5, #29
	BEQ TimerInterrupt
	
	//Push button control
	CMP R5, #73
	BEQ PushInterrupt
	
	UNEXPECTED:
	BNE UNEXPECTED // if not recognized, stop here
	
	PushInterrupt:
		BL PUSH_ISR
		B EXIT_IRQ
	
	TimerInterrupt:
		BL TIMER_ISR
		
EXIT_IRQ:
	/* Write to the End of Interrupt Register (ICCEOIR) */
	STR R5, [R4, #0x10] 	//write to ICCEOIR
	POP {R0-R7, LR}
	SUBS PC, LR, #4
/*--- FIQ ---------------------------------------------------------------------*/
SERVICE_FIQ:
	B SERVICE_FIQ

/* ^^^^ END of Define the exception service routines ^^^^ */

/* Configure the Generic Interrupt Controller (GIC)*/
CONFIG_GIC:
	PUSH {LR}
/* CONFIG_INTERRUPT (int_ID (R0), CPU_target (R1)); */
	
	//TIMER
	MOV R0, #29			// Interrupt ID = 29
	MOV R1, #1			// this field is a bit-mask; bit 0 targets cpu0
	BL CONFIG_INTERRUPT
	
	//PUSH BUTTONS
	MOV R0, #73 			// Interrupt ID = 73
	MOV R1, #1 			// this field is a bit-mask; bit 0 targets cpu0
	BL CONFIG_INTERRUPT
	
	/* configure the GIC CPU Interface */
	LDR R0, =0xFFFEC100 		// base address of CPU Interface
	
	/* Set Interrupt Priority Mask Register (ICCPMR) */
	LDR R1, =0xFFFF 		// enable interrupts of all priorities levels
	STR R1, [R0, #0x04]
	
	/* Set the enable bit in the CPU Interface Control Register (ICCICR).
	* This allows interrupts to be forwarded to the CPU(s) */
	MOV R1, #1
	STR R1, [R0]
	
	/* Set the enable bit in the Distributor Control Register (ICDDCR).
	* This enables forwarding of interrupts to the CPU Interface(s) */
	LDR R0, =0xFFFED000
	STR R1, [R0]
	POP {PC}

/*
* Configure registers in the GIC for an individual Interrupt ID
* We configure only the Interrupt Set Enable Registers (ICDISERn) and
* Interrupt Processor Target Registers (ICDIPTRn). The default (reset)
* values are used for other registers in the GIC
* Arguments: R0 = Interrupt ID, N
* R1 = CPU target
*/
CONFIG_INTERRUPT:
	PUSH {R1-R5, LR}
/* Configure Interrupt Set-Enable Registers (ICDISERn).
* reg_offset = (integer_div(N / 32) * 4
* value = 1 << (N mod 32) */
	LSR R4, R0, #3 		// calculate reg_offset
	BIC R4, R4, #3 		// R4 = reg_offset
	LDR R2, =0xFFFED100
	ADD R4, R2, R4 		// R4 = address of ICDISER
	AND R2, R0, #0x1F 	// N mod 32
	MOV R5, #1 		// enable
	LSL R2, R5, R2 		// R2 = value
	
/* Using the register address in R4 and the value in R2 set the
* correct bit in the GIC register */
	LDR R3, [R4] 		// read current register value
	ORR R3, R3, R2 		// set the enable bit
	STR R3, [R4] 		// store the new register value
	
/* Configure Interrupt Processor Targets Register (ICDIPTRn)
* reg_offset = integer_div(N / 4) * 4
* index = N mod 4 */
	BIC R4, R0, #3 		// R4 = reg_offset
	LDR R2, =0xFFFED800
	ADD R4, R2, R4 		// R4 = word address of ICDIPTR
	AND R2, R0, #0x3 		// N mod 4
	ADD R4, R2, R4 		// R4 = byte address in ICDIPTR
	
/* Using register address in R4 and the value in R2 write to
* (only) the appropriate byte */
	STRB R1, [R4]
	POP {R1-R5, PC}

/*************************************************************************
* TIMER - Interrupt Service Routine
**************************************************************************/
TIMER_ISR:
	//Toggle TIMER
	LDR R0, =TIMER
	LDR R1, [R0]
	EOR R1, R1, #1
	STR R1, [R0]

	//Interrupt Acknowledge
	LDR R0, =TIMER_BASE
	LDR R2, [R0, #12] 	//timer interrupt at 0x0FFFEC600 + 3 bytes
	STR R2, [R0, #12] 	//reset interrupt
	BX LR

/*************************************************************************
* PUSH BUTTON - Interrupt Service Routine
**************************************************************************/
PUSH_ISR:
	//Get Random Choice for computer with timer
	//00-> try again
	//01-> rock
	//10-> paper
	//11-> scissors
	random:
		LDR R0, =TIMER_BASE
		LDR R1, [R0, #4]
		LSR R1, #22
		LSL R1, #30
		LSR R1, #30
		MOV R0, R1
		CMP R0, #0
		BEQ random
	
	//assign COMP choice
	LDR R1, =COMP_CHOICE
	STR R0, [R1]
	
	//Acknowledge the interrupt
	LDR R0, =PUSH_BASE 		// base address of pushbutton KEY port
	LDR R1, [R0, #0xC] 		// read edge capture register
	MOV R2, #0xF
	STR R2, [R0, #0xC] 		// clear the interrupt

CHECK_KEY0:
	MOV R3, #0x1
	ANDS R3, R3, R1 // check for KEY0
	BEQ CHECK_KEY1
	
	//Toggle PLAY
	LDR R0, =PLAY
	LDR R1, [R0]
	EOR R1, R1, #1
	STR R1, [R0]
	
	B END_KEY_ISR
	
CHECK_KEY1: 	//ROCK -> 01
	MOV R3, #0x2
	ANDS R3, R3, R1 // check for KEY1
	BEQ CHECK_KEY2
	
	//Check whether is in Paused state
	LDR R0, =PLAY
	LDR R1, [R0]
	CMP R1, #0
	BEQ END_KEY_ISR
	
	//Assign user choice
	MOV R0, #1
	LDR R1, =USER_CHOICE
	STR R0, [R1]
	
	LDR R0, =TURN_PLAYED
	MOV R1, #1
	STR R1, [R0]
	
	B END_KEY_ISR
	
CHECK_KEY2: 	//PAPER -> 10
	MOV R3, #0x4
	ANDS R3, R3, R1 // check for KEY2
	BEQ IS_KEY3
	
	//Check whether is in Paused state
	LDR R0, =PLAY
	LDR R1, [R0]
	CMP R1, #0
	BEQ END_KEY_ISR
	
	//Assign user choice
	MOV R0, #2
	LDR R1, =USER_CHOICE
	STR R0, [R1]
	
	LDR R0, =TURN_PLAYED
	MOV R1, #1
	STR R1, [R0]
	
	B END_KEY_ISR
	
IS_KEY3: 	//SCISSORS -> 11
	//Assign user choice
	MOV R0, #3
	LDR R1, =USER_CHOICE
	STR R0, [R1]
	
	//Check whether is in Paused state
	LDR R0, =PLAY
	LDR R1, [R0]
	CMP R1, #0
	BEQ END_KEY_ISR
	
	LDR R0, =TURN_PLAYED
	MOV R1, #1
	STR R1, [R0]
	
END_KEY_ISR:
	LDR R0, =TURN_PLAYED
	LDR R1, [R0]
	CMP R1, #0
	BEQ EndOfInterrupt
	
	//calculate result
	//USER R1, COMP R2
	LDR R0, =USER_CHOICE
	LDR R1, [R0]
	LDR R0, =COMP_CHOICE
	LDR R2, [R0]
	
	//DRAW -> 0
	//COMP -> 1
	//USER -> 2
	MOV R3, #0	//RESULT
	MOV R0, #0	//SUM
	
	//Draw Condition
	CMP R1,R2
	BEQ Calculated
	
	ADD R0,R1,R2
	CMP R0, #3
	BEQ PaperWon
	CMP R0, #4
	BEQ RockWon
	CMP R0, #5
	BEQ ScissorsWon
	
	PaperWon:		//Who is paper?
		CMP R1, #2
		BEQ UserPaper
		CompPaper:
			MOV R3, #1
			B Calculated
		UserPaper:
			MOV R3, #2
		B Calculated
		
	RockWon: 		//Who is rock?
		CMP R1, #1
		BEQ UserRock
		CompRock:
			MOV R3, #1
			B Calculated
		UserRock:
			MOV R3, #2
		B Calculated
	
	ScissorsWon:	//Who is scissors?
		CMP R1, #3
		BEQ UserScissors
		CompScissors:
			MOV R3, #1
			B Calculated
		UserScissors:
			MOV R3, #2
		
	Calculated:
		//Write result to the RESULT
		LDR R0, =RESULT
		STR R3, [R0]
	EndOfInterrupt:
		BX LR

end: B end
//WELCOME: HELLO THIS IS ROCK PAPER SCISSORS GAME
ANIMATION: .byte 0x20, 0x60, 0x44, 0x0C, 0x18, 0x50, 0x42, 0x02
WELCOME: .byte 0x00, 0x00, 0x00, 0x00,0x00, 0x00, 0x00, 0x00, 0x76, 0x79, 0x38, 0x38, 0x5C, 0x00, 0x78, 0x76, 0x30, 0x6D,0x00, 0x30, 0x6D,0x00, 0x50, 0x5C, 0x39, 0x75, 0x00, 0x73, 0x77 ,0x73, 0x79, 0x50,0x00, 0x6D, 0x39, 0x30, 0x6D, 0x6D, 0x5C,  0x50, 0x6D,0x00, 0x3D, 0x77, 0x55, 0x79, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,0x00,0x00 
LETSPLAY: .byte 0x38, 0x79, 0x78, 0x6D, 0x00, 0x73, 0x38, 0x77, 0x6E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
ROCK: .byte 0x50, 0x5C, 0x39, 0x75, 0x00, 0x40, 0x00, 0x5C
PAPER: .byte 0x73, 0x77 ,0x73, 0x79, 0x50, 0x40, 0x00, 0x3F
SCISSORS: .byte 0x6D, 0x39, 0x30, 0x6D, 0x6D, 0x40, 0x00, 0x5E
BUTTONS: .byte 0x7C, 0x3E, 0x78, 0x78, 0x5C, 0x54, 0x6D, 0x00
ROCK_BUTTON: .byte 0x50, 0x5C, 0x39, 0x75, 0x00, 0x40, 0x00, 0x06
PAPER_BUTTON: .byte 0x73, 0x77 ,0x73, 0x79, 0x50, 0x40, 0x00, 0x5B
SCISSORS_BUTTON: .byte 0x6D, 0x39, 0x30, 0x6D, 0x6D, 0x40, 0x00, 0x4F
PLAY_PAUSE_BUTTON: .byte 0x73, 0x38, 0x77, 0x6E, 0x00, 0x5C, 0x50, 0x00, 0x73, 0x77, 0x3E, 0x6D, 0x79, 0x00, 0x7C, 0x3E, 0x78, 0x78, 0x5C, 0x54, 0x00, 0x40, 0x00, 0x3F
START: .byte 0x6D, 0x78, 0x77, 0x50, 0x78, 0x00, 0x00, 0x3F
CHOOSE: .byte 0x00, 0x39,0x76,0x5C,0x5C,0x6D,0x79,0x00
PAUSE: .byte  0x73,0x77,0x3E,0x6D,0x79,0x5E,0x00,0x00
END: .byte  0x79, 0x54,0x5E,0x00,0x00,0x00,0x00,0x00
DRAW: .byte 0x00, 0x00, 0x78, 0x30, 0x79, 0x00, 0x00, 0x00
COMP_WON: .byte 0x39, 0x5C, 0x55, 0x73, 0x00, 0x1D, 0x5C, 0x54
YOU_WON: .byte 0x6E, 0x5C, 0x3E, 0x00, 0x00,  0x1D, 0x5C, 0x54
YOU_VS_COMP: .byte 0x6E, 0x5C, 0x3E, 0x40,0x39, 0x5C, 0x55, 0x73
ICONS: .byte 0x00,0x5C,0x3F,0x5E,0x00,0x00,0x00,0x00
NUMBERS: .byte 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x00, 0x00
TIMER: .word 0x0 		//initially 0
PLAY: .word 0x0			//initially 0
COMP_SCORE: .word 0x0	//initially 0
USER_SCORE: .word 0x0	//initially 0
COMP_CHOICE: .word 0x0	//initially 0
USER_CHOICE: .word 0x0	//initially 0
RESULT: .word 0x0 		//initially 0
TURN_PLAYED: .word 0x0  //initially 0
NOT_FINISH: .word 0x1	//initially 1
.end