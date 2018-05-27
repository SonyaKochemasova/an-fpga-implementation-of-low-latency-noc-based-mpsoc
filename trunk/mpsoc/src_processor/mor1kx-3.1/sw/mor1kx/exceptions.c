#include "mor1kx-utils.h"
#include "int.h" // User interrupt handler header
//#include "uart.h"
//#include "../mor1ktest.h"









/*  sim_uart0   */
 #define sim_DATA_REG					(*((volatile unsigned int *) (0Xa5000000)))

void sim_putchar(char ch){ //print one char from jtag_uart
	sim_DATA_REG=ch;
}
















#define STR_EXCEPTION_OCCURED " exception occured.\n"

char *exception_strings[] = {
  "An unknown",             // 0
  "A reset (?!)",           // 1 
  "A Bus Error",            // 2
  "A Data Page Fault",      // 3
  "An Instruction Page Fault", // 4
  "A Tick-Timer",              // 5
  "An Alignment",              // 6
  "An Illegal Instruction",    // 7
  "An External Interrupt",     // 8
  "A D-TLB Miss",              // 9
  "An I-TLB Miss",             // a
  "A Range",                   // b
  "A System Call",             // c
  "A Floating-Point",          // d
  "A Trap",                    // e
  "A \"Reserved\"",            // f
  "A \"Reserved\"",            // 10
  "A \"Reserved\"",            // 11
  "A \"Reserved\"",            // 12
  "A \"Reserved\"",            // 13
  "A \"Reserved\"",            // 14
  "An Implementation Specific \"Reserved\"", // 16
  "An Implementation Specific \"Reserved\"", // 17
  "An Implementation Specific \"Reserved\"", // 18
  "A Custom",                                // 19
  "A Custom",                                // 1a
  "A Custom",                                // 1b
  "A Custom",                                // 1c
  "A Custom",                                // 1d
  "A Custom",                                // 1e
  "A Custom",                                // 1f
};

extern void int_main(void);
extern void cpu_timer_tick(void);

void (*except_handlers[]) (void)  = {0,    // 0
				    0,    // 1
				    0,    // 2
				    0,    // 3
				    0,    // 4
				    cpu_timer_tick,    // 5
				    0,    // 6
				    0,    // 7
				    int_main,    // 8
				    0,    // 9
				    0,    // a
				    0,    // b
				    0,    // c
				    0,    // d
				    0,    // e
				    0,    // f
				    0,    // 10
				    0,    // 11
				    0,    // 12
				    0};    // 13
  

void
add_handler(unsigned long vector, void (*handler) (void))
{
  except_handlers[vector] = handler;
}

struct exception_state * current_exception_state_struct;

void 
default_exception_handler_c(unsigned exception_address, unsigned epc, unsigned esr,
			    struct exception_state * exception_state)
{
  int exception_no = (exception_address >> 8) & 0x1f;
  if (except_handlers[exception_no])
    {	    
            current_exception_state_struct = exception_state;
	    (*except_handlers[exception_no])();
	    return;
    }

  // init uart here, incase it hasn't been
  //uart_init(DEFAULT_UART);
	  
  //printf("EPC = 0x%.8x\n", exception_address);
	  
  // Output initial messaging using low-level functions incase
  // something really bad happened.
  //printf("%s%s", exception_strings[exception_no],  STR_EXCEPTION_OCCURED);
//sim_putchar(exception_no+'0');	  
  // Icing on the cake using fancy functions
  //printf("EPC = 0x%.8x\n", epc);
  
  report(exception_address);
  report(epc);
  __asm__("l.nop 1");
  for(;;);
}


