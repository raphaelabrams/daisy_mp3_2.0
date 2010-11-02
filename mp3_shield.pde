//daisy mini v0.1



//0   serial from host
//1   serial to host
#define VS1011_DREQ 2     // input: active high: decoder is ready for 32 bytes more data
#define INTERRUPT 3
#define SD_XCS 4
#define LED0 5
#define LED1 6
#define VS1011_XRESET  7
#define VS1011_XDCS 8     // output: active low: select the SD card for SPI0
#define LED2 9
#define VS1011_XCS 10     // 
#define SPI_MOSI 11     // SPI data out, as the arduino sees it
#define SPI_MISO 12     // SPI data in, as the arduino sees it
#define SPI_CLOCK 13     // SPI clock, as the arduino sees it
//14  defined as analog input below
#define BUTTON0 15
#define REPORT  16
#define BUTTON1 17


#define MODE0 18  
#define MODE1 19



//analog defines
//18 amd 19 are taken by digital functions
#define VOLUME 0     // analog input: volume knob option


//for the "message" routine
#define QUEEN        'q'
#define KING        'k'
#define PIE         'p'
#define UNRELIABLE  '?'
#define YES         'y'
#define NO          'n'
#define FAIL        'f'

#define VERBOSE     1
#define QUIET       0



//spi defines for speed:
//Don't fear the C preprocessor! It is good!
#define SPI_OUT(x) (SPDR = (x))
#define SPI_IN      SPDR  //read this to get the data on the spi buffer
#define SPI_WAIT()    while (!(SPSR & (1<<SPIF))){;}
#define NOP() __asm__("nop\n\t")  //Wait one processor cycle. Good for making sure pulses aren't too short and other tiny delays.





//char SD_card_buffer[512];
int nullify=0;
char SDHC=0;


/////////////////////////////////////////////////////////////////
void setup() {
  pinMode(VS1011_DREQ, INPUT);
  pinMode(INTERRUPT, INPUT);
  pinMode(SD_XCS, OUTPUT);  
  pinMode(LED0, OUTPUT);
  pinMode(LED1, OUTPUT);
  pinMode(LED2, OUTPUT);
  pinMode(VS1011_XRESET, OUTPUT);
  pinMode(VS1011_XDCS, OUTPUT);
  pinMode(VS1011_XCS, OUTPUT);
  pinMode(SPI_MOSI, OUTPUT);
  pinMode(SPI_CLOCK, OUTPUT);
  pinMode(SPI_MISO, INPUT);  
  pinMode(BUTTON0, INPUT);  
  pinMode(REPORT, OUTPUT);
  pinMode(BUTTON1, INPUT);  
  pinMode(MODE0, INPUT);  
  pinMode(MODE1, INPUT);  
  Serial.begin(9600);
}
/////////////////////////////////////////////////////////////////
void loop() {
long la, lb;
  digitalWrite(VS1011_XDCS, 1);
  digitalWrite(VS1011_XCS, 1);
  ledflash(3,50);
 // message(KING);
  enable_spi();
  Serial.println("````step one");
  slow_spi();
  Serial.println("````step two");

  reset_vs1011(VERBOSE);
  Serial.println("````step three");
  sd_init(VERBOSE);
  Serial.println("````step four");
//  fast_spi();
  Serial.println("````step five");
  find_bpb();
  Serial.println("````step six");
//  read_sector_to_serial(0);
//  while(1){;}
  set_volume(200,200);
  Serial.println("step seven");
// read_sector_to_serial(0);

  delay(10000);
//  for(la=10000;la<1000000;la++){
//    read_sector_to_vs1011(la);
//  }
} 



unsigned long BPB_secperclus;
unsigned long BPB_start;
unsigned long BPB_firstdatasector;
unsigned long BPB_resvdseccnt;
unsigned long BPB_fatstart;
unsigned long BPB_datsec;
unsigned long BPB_bytespersec;
unsigned long BPB_FATSz32;
unsigned long BPB_rootclus;
unsigned long BPB_numFATs;
unsigned long ccl;
unsigned long pccl;
unsigned long root_ccl;
unsigned long root_p_cl;

void find_bpb(){

  long bigtemp;
	BPB_start=0;
	sd_open_block(0);
	sd_skip(0x1C6);
	

	BPB_start=(RecSPI());
	BPB_start+=(RecSPI()*256);
	sd_skip(54);

	sd_close_block();
	sd_open_block((long) BPB_start);

	sd_skip(11);
	BPB_bytespersec=RecSPI();	//11
	BPB_bytespersec+=((int) RecSPI()*256); //11.12
	BPB_secperclus=RecSPI();	//13
	BPB_resvdseccnt=RecSPI();
	BPB_resvdseccnt+=((int) RecSPI()*256);  //14.15

	BPB_numFATs=RecSPI();  //16      //BPB_RootEntCnt=data_hi;  //17
	sd_skip(20);

	BPB_FATSz32=0;
	BPB_FATSz32=RecSPI();
        BPB_FATSz32+=((long) RecSPI()*256);  //36.37
	bigtemp=BPB_FATSz32;
	
	BPB_FATSz32=RecSPI();
        BPB_FATSz32+=((long) RecSPI()*256);  //36.37.38.39
	BPB_FATSz32=BPB_FATSz32 << 16;
	BPB_FATSz32=bigtemp+BPB_FATSz32;
	sd_skip(4);
	BPB_rootclus=RecSPI();
        BPB_rootclus+=((long) RecSPI()*256);  //44.45
	bigtemp=BPB_rootclus;

	
	BPB_rootclus=RecSPI();
        BPB_rootclus+=((long) RecSPI()*256);  //44.45.46.47
	BPB_rootclus=BPB_rootclus<<16;
	BPB_rootclus=BPB_rootclus+bigtemp;
	root_ccl=BPB_rootclus;

	sd_skip(464);
	sd_close_block();

	BPB_fatstart=BPB_start+BPB_resvdseccnt;
	BPB_firstdatasector = BPB_resvdseccnt + (BPB_numFATs * BPB_FATSz32);// + RootDirSectors;
	BPB_datsec = (long)BPB_start + (long)BPB_firstdatasector;
	Serial.print("some info about card:");
	Serial.print(" bpbst"); Serial.println(BPB_start,DEC); 
	Serial.print(" BPB_bpsec"); Serial.println(BPB_bytespersec,DEC); 
	Serial.print(" BPB_ScPeC"); Serial.println(BPB_secperclus,DEC); 
	Serial.print(" BPB_RsvdScCt"); Serial.println(BPB_resvdseccnt,DEC); 
	Serial.print(" BPB_NmFAT"); Serial.println(BPB_numFATs,DEC); 
	Serial.print(" fatstart"); Serial.println(BPB_fatstart,DEC); 
	Serial.print(" FirstDataSector"); Serial.println(BPB_firstdatasector,DEC);
}






/*
int32 readfat(int32 fatoffset){
//super fat :::::
//-----------------------------------
char holderizer0,holderizer1;
int16 temp;
char looper;
int32 tempb;
char los;


	temp=0;
	los = *(((char*)&fatoffset)+0);	//the bottom byte of the address goes directly to a word in the FAT
	fatoffset=fatoffset / 128; 
	fatoffset+=fatstart;

	if(fat_pointer!=fatoffset){
		fat_pointer=fatoffset;
		if(mmc_open_block(fatoffset)==1){
			putc('^');
				//		printf("fat retry...");
			if(mmc_open_block(fatoffset)==1){
				putc('&');
				mmc_init(0);
				if(mmc_open_block(fatoffset)==1){
					putc('*');
					mmc_init(0);
					if(mmc_open_block(fatoffset)==1){
						return 0xffffffff;
					}
				}
			}
		}
		looper=0;
		do{
			mmc_read();
			fat_buffer_lo[looper]=data_lo;
			fat_buffer_hi[looper]=data_hi;
			looper++;
		}while(looper>0);

			mmc_read();
			mmc_read();
			mmc_close_block();
	}

	holderizer0 = fat_buffer_lo[(los*2)];
	holderizer1 = fat_buffer_hi[(los*2)];
	temp = ((int16) holderizer1 * 256)+ (int16) holderizer0 ;
	tempb=0;

	holderizer0 = fat_buffer_lo[(los*2)+1];
	holderizer1 = fat_buffer_hi[(los*2)+1];
	tempb = ((int16) holderizer1 * 256)+ (int16) holderizer0;

	tempb=tempb<<16;
	tempb=tempb+(int32) temp;

	return tempb;
}

*/

void read_sector_to_serial(long x){
long foo=0;
int foofoo=0;
  sd_open_block(x);
  for(foo=16;foo>0;foo--){
    for(foofoo=32;foofoo>0;foofoo--){
      Serial.print(SendRecSPI(0xff));
    }
      Serial.println(" ");
  }
  sd_close_block();
}

/////////////////////////////
int read_sector_to_vs1011(long sector){
byte i;
int ii, bufferpointer;
 byte fbuffer[512];

  digitalWrite(VS1011_XDCS,1);
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(LED0,1);
  if(!SDHC){sector*=512;}
  SendSPI(0xFF);
  SendSPI(0xFF);
  digitalWrite(SD_XCS,0);                     // set SD_XCS = 0 (on)
  SendSPI(0x51);                // send sd read single block command
  SendSPI(*(((char*)&sector)+3)); // arguments are address
  SendSPI(*(((char*)&sector)+2));
  SendSPI(*(((char*)&sector)+1));
  SendSPI(*(((char*)&sector)+0));
  SendSPI(0xFF);                // checksum is no longer required but we always send 0xFF

  if(sd_response(0x00)==0) {
    SendSPI(0xFF);
    SendSPI(0xFF);
    digitalWrite(SD_XCS,1); // deselect sd card (off)
    SendSPI(0xFF);// give sd the clocks it needs to finish off
    SendSPI(0xFF);
    Serial.println("vs_loop: SD failed on 0x00");
    return 0; 
  }

  if(sd_response(0xFE)==0){
    SendSPI(0xFF);
    SendSPI(0xFF);
    digitalWrite(SD_XCS,1); // deselect sd card (off)
    SendSPI(0xFF);// give sd the clocks it needs to finish off
    SendSPI(0xFF);
    Serial.println("vs_loop SD failed on 0xFE");
    return 0;
  }

  SPDR = 0xff;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
  for(ii=0;ii<512;ii++){
    NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();

  //  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
      fbuffer[ii]=SPDR;
      SPDR = 0xff;
  }

  SendSPI(0xFF);                 // CRC bytes that are not needed, so we just use 0xFF
  SendSPI(0xFF);
  digitalWrite(SD_XCS,1);        // deselect SD card
  SendSPI(0xFF);// give sd the clocks it needs to finish off
  SendSPI(0xFF);
  digitalWrite(LED0,0);
  digitalWrite(LED1,1);
  digitalWrite(VS1011_XDCS, 0);
  bufferpointer=0;
  for(i=16;i>0;i--){
    while(digitalRead(VS1011_DREQ)==0){;}
    for(ii=0;ii<32;ii++){
//      while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission  SendSPI(fbuffer[bufferpointer++]);
      NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();
      SPDR=fbuffer[bufferpointer];
      bufferpointer++;
    }
  }
  digitalWrite(VS1011_XDCS,1); //deselect the vs1011 spi port
  digitalWrite(LED1,0);
  return 1; //we did it! We read a sector 
}


////////////////////////////



unsigned int VS_command(unsigned char a,unsigned char b, unsigned char c, unsigned char d){      
unsigned int temp;
  digitalWrite(VS1011_XCS, 0);
  SendRecSPI(a);
  SendRecSPI(b);
  temp = SendRecSPI(c);
  temp=temp*256;
  temp+=SendRecSPI(d);		
  digitalWrite(VS1011_XCS, 1);
  return temp;
}

void set_volume( char l, char r){
  VS_command(0x02,0x0b,255-l,255-r);
}

void reset_vs1011(char verbosity){
  delay(5);
  digitalWrite(VS1011_XRESET, LOW);
  delay(1);
  digitalWrite(VS1011_XRESET, HIGH);
  delay(3);
  VS_command(0x02,0x00,0x00,0x04);
  VS_command(0x02,0x00,0x08,0x00);
  VS_command(0x02,0x0b,0x20,0x20);
  if(verbosity==VERBOSE){
    Serial.print("Vs1011 volume register is: ");
    Serial.println(VS_command(0x03,0x0b,0xff,0xff), HEX);
  }
 digitalWrite(VS1011_XCS, 1);
  digitalWrite(VS1011_XDCS, 1);
}

void sine_test(void){

  VS_command(0x02,0x00,0x08,0b00100000);
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(VS1011_XDCS, 0);
  delay(1);
  SendRecSPI(0x53);SendRecSPI(0xef);
  SendRecSPI(0x6e);SendRecSPI(0b01111110);
  SendRecSPI(0);SendRecSPI(0);
  SendRecSPI(0);SendRecSPI(0);
  delay(1000);
  SendRecSPI(0x45);  SendRecSPI(0x78);
  SendRecSPI(0x69);  SendRecSPI(74);
  SendRecSPI(0);  SendRecSPI(0);
  SendRecSPI(0);  SendRecSPI(0);
  delay(1000);
  digitalWrite(VS1011_XDCS, 1);
  delay(1);
}

//////////////////////////////////////////////////SD card routines///////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////////////////////////
void sd_skip(int count){
	for (;count>0;count--){
		SendSPI(0xFF);
	}
}
////////////////////////////////////////////////////////////////////////////////////////////////

char sd_open_block(long block_number){
char tries,i;
long block_number_temp;
  block_number_temp=block_number;     //for SDHC
    if(!SDHC){block_number_temp*=512;}

    SendRecSPI(0xFF);
    SendRecSPI(0xFF);
    digitalWrite(SD_XCS,0);                     // set SD_XCS = 0 (on)
    SendRecSPI(0x51);                // send sd read single block command
    SendRecSPI(*(((char*)&block_number_temp)+3)); // arguments are address
    SendRecSPI(*(((char*)&block_number_temp)+2));
    SendRecSPI(*(((char*)&block_number_temp)+1));
    SendRecSPI(*(((char*)&block_number_temp)+0));
    SendRecSPI(0xFF);                // checksum is no longer required but we always send 0xFF
    if((sd_response(0x00))==1){//((sd_response(0x00))==0){
      if((sd_response(0xFE))==1){
        return(1);	
      }
    for(i=0;i<255;i++){
      SendRecSPI(0xFF);
      SendRecSPI(0xFF);
    }
  }
  digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
  SendRecSPI(0xFF);// give sd the clocks it needs to finish off
  SendRecSPI(0xFF);// give sd the clocks it needs to finish off
  return 0;
}

void sd_close_block(void){
  SendSPI(0xFF);                 // CRC bytes that are not needed
  SendSPI(0xFF);
  digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
  SendSPI(0xFF);                // give sd the clocks it needs to finish off
  SendSPI(0xff);
}


void sd_cancel_block(void){
  digitalWrite(SD_XCS,1);
  SendSPI(0xFF);	
  SendSPI(0xFF);
  digitalWrite(SD_XCS,0);
  SendSPI(0xFF);
  SendSPI(0x4C);                // send sd cancel block command
  SendSPI(0);
  SendSPI(0);
  SendSPI(0);
  SendSPI(0);
  SendSPI(0xFF);
  sd_response(0x00);
  digitalWrite(SD_XCS,1);
  SendSPI(0xFF); 
  SendSPI(0xff);
}


////////////////////////////////////////////////////////////////////////////////////////////////////
char SD_command(char command, char a, char b, char c, char d, char check){
unsigned char response;
  command |= 0b01000000;
  SendSPI(command);
  SendSPI(a);
  SendSPI(b);
  SendSPI(c);
  SendSPI(d);
  SendSPI(check);
  for(char i = 0; i < 10; ++i){
    response =   RecSPI();
    Serial.print(command & 0b10111111,DEC); Serial.print(" SD_command loop returns: HEX> "); Serial.print(response,HEX); Serial.print("  BINARY> "); Serial.println(response,BIN);
    if(response != 0xff){
      return response;
    }
  }
}
  
void SD_printabyte(void){
unsigned char  response;
  response =   RecSPI();
  Serial.print(response);    
  Serial.print("--"); 
  Serial.print(response,HEX);    
  Serial.print("-"); 
  Serial.println(response,BIN);
}

int sd_init(bool report){	//Initialises the sd into SPI mode and sets block size
//char p;
int i, ii, tries;
unsigned char n, cmd; 
byte ocr[4]={0,0,0,0};

  delay(30);	
  digitalWrite(SD_XCS,1);			//                    // set SD_XCS = 1 (off)
  delay(30);
  for(i=0;i<10;i++){                       // initialise the sd card into SPI mode by sending clks on
    SendSPI(0xFF);
  }
  digitalWrite(SD_XCS,0);				                     // set SD_XCS = 0 (on) tells card to go to spi mode when it receives reset

  for(i=0; i<100; i++){
    if(report){Serial.println("executing command 0");}
    if(SD_command(0,0,0,0,0,0x95)==1){//
      if(report){Serial.println("Got response from command 0");}
      break;
    }
  }  
  SD_printabyte();
  SD_printabyte();
  SD_printabyte();
 
  SD_command(0x08, 0,0,0x01,0xaa,0x87);
  for (n = 0; n < 4; n++){ 
    ocr[n] = RecSPI(); 
    if(report){Serial.print("__OCR SAYS: "); Serial.print(ocr[n],HEX); space();}
  } /* Get trailing return value of R7 resp */
  if (ocr[2] == 0x01 && ocr[3] == 0xAA) { /* The card can work at vdd range of 2.7-3.6V */
    if(report){Serial.println("if the pattern above is '0,0,1,AA' then this is probably sd v2, ie SDHC"); SDHC=1;} //SDHC = 1 but it may be set back to 0 in the next test
  }else{if(report){Serial.println("patterns don't match, probably not SD 2.0");}}
  SD_printabyte();



  if(report){Serial.println("SD init: command55...");}
  SD_command(55,0,0,0,0,0xFF);//while(sd_response_masked(0b10000000)==0){
  if(report){Serial.println("SD init: ACMD41...");}
SD_printabyte();


  Serial.print("SDHC <<6 is"); 
  Serial.println(SDHC<<6,BIN);

  if (SD_command(41,SDHC<<6,0,0,0,0xFF) <= 0x01){
    if(report){Serial.println("yes, it's an sd!");}    if(report){Serial.println("Giant Boner!");}
  }
SD_printabyte();

  
  if(report){Serial.println("command 58:");}
    SD_command (0x58, 0,0,0,0,0xff);
  for (n = 0; n < 4; n++){ 
    ocr[n] = RecSPI(); 
    if(report){Serial.println(ocr[n],HEX);}
    if(!(ocr[0] & 0b01000000)){SDHC=0;}
  }

  if(report){Serial.println("command 16:");}
  SD_command(16,0,0,0x02,0,0xFF);       // block size command

  digitalWrite(SD_XCS,1);            //off
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 
  SendSPI(0xff);                // 


  if(SDHC){Serial.println("SDHC is go!");}


//  digitalWrite(SD_XCS,0);
//  sd_open_block(0);
//  for(i=0;i<520;i++){SD_printabyte();}
//  digitalWrite(SD_XCS,1);
  return 1; //good



}
	



////////////////////////////////////////////////////////////////////////////////////////////////
int sd_get_status(){	// Get the status register of the sd, for debugging
	digitalWrite(SD_XCS,0);                     // set SD_XCS = 0 (on)
	SendSPI(0x7a);                // 0x58?
	SendSPI(0x00);
	SendSPI(0x00);
	SendSPI(0x00);
	SendSPI(0x00);
	SendSPI(0xFF);                // checksum is no longer required but we always send 0xFF
	sd_response(0x00);
	sd_response(0xff);
	digitalWrite(SD_XCS,1);                    // set SD_XCS = 1 (off)
	SendSPI(0xFF);
	SendSPI(0xFF);
	return 0;
}

////////////////////////////////////////////////////////////////////////////////////////////////
int sd_response(unsigned char response){	//reads the sd until we get the response we want or timeout
int count;        		// 16bit repeat, it may be possible to shrink this to 8 bit but there is not much point
	for(count=520;count>0;count--){
		if(RecSPI() == response){
			return (1);
		}
	}
	return 0;
}


int sd_response_masked(unsigned char mask){	//reads the sd until we get the response we want or timeout
int count;        		// 16bit repeat, it may be possible to shrink this to 8 bit but there is not much point
	for(count=520;count>0;count--){
		if(!(mask & RecSPI())){
			return (1);
		}
	}
	return 0;
}

void fast_spi(){
    SPCR = 0b01010000;  // interrupt disable, spi enabled, MSB first, Master mode, SCK low when idle, sample on rising SCK edge, fastest clock 
    SPSR |= (1 << SPI2X); //doubled clock frequency 
}
void slow_spi(){
    SPCR = 0b01010000;  // interrupt disable, spi enabled, MSB first, Master mode, SCK low when idle, sample on rising SCK edge, fastest clock 
    SPSR |= (1 << SPI2X); //doubled clock frequency 
}

void enable_spi(void) {
 SPCR |= 1 << SPE;
}

void disable_spi(void) {
 SPCR &= ~(1 << SPE);
}
 
inline byte SendRecSPI(unsigned char Dbyte) {             // send one byte, get another in exchange
  SPDR = Dbyte;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
  return SPDR;                             // SPIF will be cleared
}

inline byte RecSPI(void) {             // send one byte, get another in exchange
  SPDR = 0xff;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
  return SPDR;                             // SPIF will be cleared
}

inline void SendSPI(unsigned char Dbyte) {             // send one byte, get another in exchange
  SPDR = Dbyte;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
}

//////////////////////////////////////////////////utility routines///////////////////////////////////////
void ledflash(int number, int duration) {  
  for(;number>0;number--){
    delay(duration/6);
    digitalWrite(LED0, HIGH);   // sets the LED on  
    delay(duration/6);                  // waits  
    digitalWrite(LED1, HIGH);    // sets the LED off  
      delay(duration/6);
    digitalWrite(LED2, HIGH);   // sets the LED on  
    delay(duration/6);                  // waits  
    digitalWrite(LED0, LOW);    // sets the LED off  
      delay(duration/6);
    digitalWrite(LED1, LOW);   // sets the LED on  
    delay(duration/6);                  // waits  
    digitalWrite(LED2, LOW);    // sets the LED off  
  }
} 

void message (char m){
  switch(m){
    case QUEEN:
      Serial.println("");
      Serial.println("I am the Queen ");
      Serial.println("of France!");
    break;

    case KING:
      Serial.println("");
      Serial.println("I am the King ");
      Serial.println("of France!");
    break;

    case PIE:
      Serial.println("");
      Serial.println("Who ate all the pie? ");
    break;

    case UNRELIABLE:
      Serial.println("");
      Serial.println("Under no circumstances should you ");
      Serial.println("listen to what I have to say.");
    break;

    case YES:
      Serial.println("");
      Serial.println("Yay!");
    break;

    case NO:
      Serial.println("");
      Serial.println("nope");
    break;

    case FAIL:
      Serial.println("");
      Serial.println("FAIL!");
    break;

    default:
      Serial.println("");
      Serial.println("Undefined message: bleuncrnuinasxms");
    break;
  }
}

void space(void){
  Serial.print(" ");
}



