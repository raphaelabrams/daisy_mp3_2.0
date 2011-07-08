//daisy mini v0.1

//#include <SD.h>

//File myFile;
#include <avr/interrupt.h> 
//#include < avr / io.h > 

#define MAXFILENAMELENGTH 65
#define MAXTREE 6
//0   serial from host //don't need to implement these lines to make serial work, these are just for reference
//1   serial to host
#define VS1011_DREQ 2     // input: active high: decoder is ready for 32 bytes more data
#define INTERRUPT 3
#define SD_XCS 4
#define LED0 5
#define BLUE 5

#define LED1 6
#define RED 6
#define VS1011_XRESET  7
#define VS1011_XDCS 8     // output: active low: select the SD card for SPI0
#define LED2 9
#define GREEN 9
#define VS1011_XCS 10     // 
#define SPI_MOSI 11     // SPI data out, as the arduino sees it
#define SPI_MISO 12     // SPI data in, as the arduino sees it
#define SPI_CLOCK 13     // SPI clock, as the arduino sees it
//14  defined as analog input below
#define REPORT  16

#define MODE0 18  
#define MODE1 19

#define BUTTON0 15
#define BUTTON1 17
#define BUTTON2  16
#define BUTTON3 3
#define BUTTON4 18  
#define BUTTON5 19




//analog defines
//18 amd 19 are taken by digital functions
#define VOLUME 0     // analog input: volume knob option



//for the commands
#define NULL_COMMAND 0
#define VOLUME 'v'//adjust both speaker volumes 
#define LEFTVOLUME 'l'//adjust the left speaker volume 
#define RIGHTVOLUME 'r'  //adjust the right speaker volume 
#define PLAYNEW  'p'      //load a new file and play it
#define HALT  'h'      //pause playback
#define CONTINUE 'c'   //resume playback
#define STOP 's'      //stop as if file has ended (cancel track)
#define LOOP_ON  'a'
#define LOOP_ON  'b'
#define NEXT  'n'      //load the next file in the directory tree (not alphabetical) and play it
#define PREVIOUS  'z'  //load the PREVIOUS file in the directory tree (not alphabetical) and play it

#define LIST '1'
#define CD '2'
#define RESETCARD '3'
#define DIR '4'
char command[MAXFILENAMELENGTH+6]={0,0,0,0};
char shellcommandindex=0;
char currentcommand=0;


#define VERBOSE     1
#define QUIET       0


//spi defines for speed:
//Don't fear the C preprocessor! It is good!
//#define SPI_OUT(x) (SPDR = (x))
//#define SPI_IN      SPDR  //read this to get the data on the spi buffer
//#define SPI_WAIT()    while (!(SPSR & (1<<SPIF))){;}
#define NOP() __asm__("nop\n\t")  //Wait one processor cycle. Good for making sure pulses aren't too short and other tiny delays.
// #define nop asm volatile ("nop\n\t")


unsigned char SDarray[512];
unsigned char directory_entry_buffer[32];
char long_file_name[MAXFILENAMELENGTH+1];
unsigned char BPB_secperclus=0;
//unsigned long BPB_start=0;
unsigned long BPB_firstdatasector=0;
unsigned long BPB_fatstart=0;
unsigned long BPB_bytespersec=0;
unsigned long BPB_rootclus=0;
unsigned long highestentry=0;

unsigned long file_start_cluster=0xffffffff;
unsigned long songlength;
unsigned char fileflags;
char SDHC=0;

unsigned char volume_left=220;
unsigned char volume_right=220;
short paused=0;

unsigned long cd_cluster[MAXTREE];
unsigned char cd_depth=0;
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
  Serial.begin(115200);

  digitalWrite(VS1011_XDCS, 1);
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(SD_XCS,1);
  digitalWrite(VS1011_XRESET, 0);

  ledflash(3,300);
  Serial.println("I am the King ");
  Serial.println("of France!");
  enable_spi();
  reset_vs1011_hard(VERBOSE);
  SD_init(VERBOSE);
  find_bpb();
  cd_cluster[cd_depth]=BPB_rootclus;
  find_highest_entry_number();

  TCCR2A = 0;	     // normal operation
  TCCR2B = (1<<CS20);   // prescaler 8
  TCCR2B = (1<<CS21);   // prescaler 8
  TCCR2B = (1<<CS22);   // prescaler 8
  TIMSK2 = (1<<TOIE2);  // enable overflow interrupt

}

/////////////////////////////////////////////////////////////////
void loop(){
  if(currentcommand==PLAYNEW){
    currentcommand=NULL_COMMAND;
    for(unsigned int i=0;i<=MAXFILENAMELENGTH;i++){
      command[i]=command[i+5];
    }
    if(find_file(command)>=0){
  //  Serial.print("playing|");    Serial.print(command);
  
      song(file_start_cluster,songlength);
    }  
  }
//  if(currentcommand==VOLUME){
//    currentcommand=NULL_COMMAND;
//    set_volume(volume_left,volume_right);
//    Serial.print("vv");Serial.print(volume_right,DEC);
//  }
  if(currentcommand==LIST){
    ls();
    currentcommand=NULL_COMMAND;
  }

  if(currentcommand==DIR){
    dir();
    currentcommand=NULL_COMMAND;
  }

  if(currentcommand==RESETCARD){
    SD_init(1);
    currentcommand=NULL_COMMAND;
  }

  if(currentcommand==CD){
    for(unsigned int i=0;i<=MAXFILENAMELENGTH;i++){
      command[i]=command[i+3];
    }
    cd(command);
    currentcommand=NULL_COMMAND;
  }
} 


ISR(TIMER2_OVF_vect) { 
  get_shell_command();
}; 

volatile void get_shell_command(void){
  if(currentcommand!=NULL_COMMAND){return;}
  if(Serial.available() > 0){
    
    char aChar = Serial.read();
    Serial.write(aChar);//echo echo echo...
    if(aChar == 10 || aChar == 13 || aChar == ';'){    //cr/lf. Parse!
    Serial.write(10);
    Serial.write(13);
//    Serial.println("commanded!!!");
      aChar=0;
      command[shellcommandindex] = aChar;

      if(strcmp("ls",command)==0){
        currentcommand=LIST;
      }

      if(strcmp("dir",command)==0){
        currentcommand=DIR;
      }

      if(strncmp(command,"cd",2)==0){
//        Serial.print("CD time:");
        currentcommand=CD;
      }
      if(strncmp(command,"play",4)==0){
        paused=0;
        currentcommand=PLAYNEW;
        VS_command(0x02,0x0b,254,254);
      }
      if(strncmp(command,"vv",2)==0){
        currentcommand=VOLUME;
        char hexDigit= toupper(command[3]);
        volume_left = (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        volume_left*=0x10;
        hexDigit= toupper(command[4]);   
        volume_left += (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        volume_right=volume_left;
      }
      if(strncmp(command,"vl",2)==0){
        char hexDigit= toupper(command[3]);
        volume_left = (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        volume_left*=0x10;
        hexDigit= toupper(command[4]);   
        volume_left += (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        currentcommand=VOLUME;
      }
      if(strncmp(command,"vr",2)==0){
        char hexDigit= toupper(command[3]);
        volume_right = (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        volume_right*=0x10;
        hexDigit= toupper(command[4]);   
        volume_right += (hexDigit >= 'A') ? hexDigit - 'A' + 10 : hexDigit - '0'; 
        currentcommand=VOLUME;
      }

      if(strcmp("pause",command)==0){
        paused=1;
//        currentcommand=HALT;
      }

      if(strcmp("resume",command)==0){
        paused=0;
  //      currentcommand=CONTINUE;
      }

      if(strcmp("stop",command)==0){
        paused=0;
//        Serial.print("stop!");
        VS_command(0x02,0x0b,254,254);
        
        currentcommand=STOP;
      }

      if(strcmp("rst",command)==0){
        currentcommand=RESETCARD;
      }

      shellcommandindex = 0;
      command[shellcommandindex] = NULL;
      Serial.print("command is");Serial.print(currentcommand);

    }

    else{
      command[shellcommandindex++] = aChar;
    }
  }  
}
/*
char comparestrings( char* buffer, char* pattern){
  char index=0;
  while(pattern[index]){
    if(buffer[index]!=pattern[index]){return 0;}
    index++;
  }
  Serial.println(index,DEC);space();
  return 1;
}



char comparestrings_forgiving( char* buffer, char* pattern){
  char index=0;
  while(pattern[index] != 0){
    if(buffer[index]!=pattern[index]){return 0;}
    index++;
  }
  Serial.println(index,DEC);space();
  return 1;
}

*/
char song(unsigned long song_cluster,unsigned long length){
        unsigned long song_previous_cluster;
        unsigned long song_sector;
  	unsigned long totalsectorsdone;
	unsigned char x = 0;
        length/=BPB_bytespersec;
	totalsectorsdone=0;  
        reset_vs1011_soft(1);
//        set_volume(200,200);
	do{
		song_sector=song_cluster-2;
		song_sector *= (unsigned long)BPB_secperclus;
		song_sector += BPB_firstdatasector;
  		for (x=0;x<BPB_secperclus;x++){
			totalsectorsdone++;
			if(totalsectorsdone<length){
  				read_sector_to_vs1011(song_sector);//this function call is where data goes to the decoder
        			song_sector++;
			}
		}
                if(currentcommand==VOLUME){
                  currentcommand=NULL_COMMAND;
                  VS_command(0x02,0x0b,255-volume_left,255-volume_right);
                  Serial.print("vv");Serial.print(volume_right,DEC);
                }
                if(currentcommand==PLAYNEW){
                  Serial.print("esc new");
                  return 3;
                }

                if(currentcommand==STOP){
                  currentcommand=NULL_COMMAND;
                  Serial.print("esc stop");
                  return 4;
                }

                if(currentcommand!=NULL_COMMAND){
                  Serial.print("sys");
                  return 5;
                }

                while(paused){
                  Serial.print(".");
                  if(currentcommand==VOLUME){
                    currentcommand=NULL_COMMAND;
                    VS_command(0x02,0x0b,255-volume_left,255-volume_right);
                  }
                  if (currentcommand != NULL_COMMAND){return 6;}             

                  delay(100);
                }

		song_previous_cluster=song_cluster;
        	song_cluster=readfat(song_previous_cluster);
	}while((song_cluster & 0x0FFFFFFF)<0x0fffffef);
	return('s');
}

void zeroes(unsigned char reps){
unsigned int bufferpointer=0; 
unsigned int ii=0;
  digitalWrite(LED0,1);
  digitalWrite(LED1,1);
  digitalWrite(LED2,1);
  digitalWrite(VS1011_XDCS,1);
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(VS1011_XDCS, 0);
  for(;reps>0;reps--){
    for(unsigned char i=16;i>0;i--){
      while(digitalRead(VS1011_DREQ)==0){;}
      for(unsigned int ii=0;ii<32;ii++){
        SendSPI(0);
      }
    }
  }
  digitalWrite(VS1011_XDCS,1); //deselect the vs1011 spi port
  digitalWrite(LED0,0);
  digitalWrite(LED1,0);
  digitalWrite(LED2,0);
}

//find a file by matching with a string
long find_file(char* filename){
  unsigned long la;
  Serial.print("namln:");Serial.println(strlen(filename),HEX);space();
  for(la=0;la<highestentry;la++){
    if(get_long_file_name(la,0)){

    if(strcmp(long_file_name,filename)==0){
//        if(strlen(filename)==strlen(long_file_name)){
          Serial.print("match:"); Serial.print(la,DEC);//space();
          Serial.print(" '");Serial.print(long_file_name);
          Serial.print("' size ");Serial.print(songlength,HEX);space();
          Serial.print(" start clust: ");Serial.println(file_start_cluster,HEX);space();
          return la ;
  //       }  
       }     
    }
  }
  for(la=0;la<highestentry;la++){
      if(get_long_file_name(la,0)){
      if(strncmp(long_file_name,filename,strlen(filename))==0){
          Serial.print("partialmatch:"); Serial.print(la,DEC);//space();
          Serial.print(" '");Serial.print(long_file_name);
          Serial.print("' size ");Serial.print(songlength,HEX);space();
          Serial.print(" start clust: ");Serial.println(file_start_cluster,HEX);space();
          return la ;
      }     
    }
  }
  Serial.println("find file fail");
  return -1;
}

char cd(char* foldername){
  if((strcmp(foldername,"..")==0)){
    if(cd_depth){
      cd_depth--;
      Serial.print("back");
      return 1;
    }else{
      Serial.print("at root.");
      return 0;
    }
  }  
  if(foldername[0]=='/'){
      cd_depth=0;
      Serial.print("at root");
      return 1;
  }
  if(find_file(foldername)>=0){
//    Serial.print("folder named!");
    if(fileflags & 0x10){
//      Serial.print("flagged!!! OMG!!!");
      cd_depth++;
      if(cd_depth==MAXTREE){
        Serial.print("already deep!");
        cd_depth=MAXTREE-1;
        return 0;
      }
      cd_cluster[cd_depth]=file_start_cluster;
      Serial.print("folder start cluster");space();Serial.print(file_start_cluster,HEX);space();
      Serial.print("folder flags");space();Serial.print(fileflags,HEX);space();
      Serial.print(long_file_name);space();
      return 1;
    }else{Serial.print("not a folder!");}
    
  }else{Serial.print("no such file or folder found!");}
  return 0;
}




//list all the files in a given directory
char ls(){
  unsigned long la;
  int totalfiles=0;
  for(la=0;la<highestentry;la++){
    if(get_long_file_name(la,1)){
      if(fileflags&0x10){Serial.print(" FOLDER");}
//      Serial.write(0x09);
      Serial.print("_ at entry number: "); Serial.print(la,HEX);space();
      Serial.print("file size");Serial.print(songlength,HEX);space();
      Serial.print("start cluster");space();Serial.println(file_start_cluster,HEX);space();
        totalfiles++;
    }
  }
  Serial.print("  total files:"); Serial.println(totalfiles,DEC);//space();
  fileflags=0;
  long_file_name[0]=0;
//  for(int i=0;i<32;i++){
//    directory_entry_buffer[i]=0;
//  }		
//    fileflags=0;    
}

//list all raw directory entries
char dir(){
  unsigned long la;
  int totalfiles=0;
  for(la=0;la<highestentry;la++){
    dump_directory_entry(la);
    if(get_long_file_name(la,0)){
  //    if(fileflags&0x10){Serial.print(" FOLDER");}
//    Serial.write(0x09);
      Serial.print("*****at entry number:"); Serial.print(la,HEX);space();
      Serial.print("file size");Serial.print(songlength,HEX);space();
      Serial.print("start cluster");space();Serial.print(file_start_cluster,HEX);space();
      Serial.println(long_file_name);
      totalfiles++;
    }
  }
  Serial.print("  total files:"); Serial.println(totalfiles,DEC);//space();
  fileflags=0;
  long_file_name[0]=0;
}



char read_directory_entry(unsigned long entrynumber, char verbose){

unsigned long directory_previouscluster=0;
unsigned long directory_cluster=cd_cluster[cd_depth];
unsigned long clusters_to_read=(entrynumber/16)/ (unsigned long)BPB_secperclus;
unsigned long sector_to_read=(entrynumber/16)-(clusters_to_read*(unsigned long)BPB_secperclus);
unsigned long entry_to_read=((entrynumber & 0x0000000F)*32);

//walk the cluster chain for the directory entry that we need...
    for(unsigned long m=0; m<clusters_to_read;m++){
      directory_previouscluster=directory_cluster;
      directory_cluster=readfat(directory_previouscluster);
      if ((directory_cluster & 0x0FFFFFFF)>0x0fffffef){
        return (0x02);
      }
    }
    directory_cluster -=2;
    directory_cluster *= (unsigned long)BPB_secperclus;
    directory_cluster+= BPB_firstdatasector;
    directory_cluster += sector_to_read;
    SD_buffer_block(directory_cluster); 
    for(int i=0;i<32;i++){
      directory_entry_buffer[i]=SDarray[entry_to_read+i];
    }		
  
//parse some of the data, if it's a real 8.3 entry
  if((directory_entry_buffer[0x0b] & 0x40)){Serial.print("DIRECTORY ENTRY ALERTTTTTT");}
  if((directory_entry_buffer[0x0b]!=0x0f)&&(directory_entry_buffer[0] != 0xe5)&&(directory_entry_buffer[0] != 0)){
    file_start_cluster=(unsigned long)directory_entry_buffer[26];
    file_start_cluster+=((unsigned long)directory_entry_buffer[27]*0x100);
    file_start_cluster+=((unsigned long)directory_entry_buffer[20]*0x10000);
    file_start_cluster+=((unsigned long)directory_entry_buffer[21]*0x1000000);
    *(((char*)&songlength)+0)=directory_entry_buffer[28];
    *(((char*)&songlength)+1)=directory_entry_buffer[29];
    *(((char*)&songlength)+2)=directory_entry_buffer[30];
    *(((char*)&songlength)+3)=directory_entry_buffer[31];
    fileflags=directory_entry_buffer[0x0b];
    unsigned char lfnchecksum=0;//for long filename checksum calculation. start with a zero.
    for (unsigned char i = 0; i < 11; i++) {
      lfnchecksum = (((lfnchecksum & 1) << 7) | ((lfnchecksum & 0xfe) >> 1)) + directory_entry_buffer[i];
    }
  //  compare lfnchecksum with directory_entry_buffer[13])
    if(verbose){
      Serial.print("entry number");space();Serial.print(entrynumber,HEX);space();
      for(char i=0;i<11;i++){
        Serial.print(directory_entry_buffer[i]);
      }
      space();
      Serial.print("songlength");space();Serial.print(songlength,HEX);space();
      Serial.print("start cluster");space();Serial.print(file_start_cluster,HEX);space();
      Serial.print("flags");space();Serial.print(fileflags,BIN);
      Serial.print("LFN checksum");space();Serial.println(lfnchecksum,HEX);
    }
    return(0x01);
  }
  return(0x00);
}


char dump_directory_entry(unsigned long entrynumber){

unsigned long directory_previouscluster=0;
unsigned long directory_cluster=cd_cluster[cd_depth];
unsigned long clusters_to_read=(entrynumber/16)/ (unsigned long)BPB_secperclus;
unsigned long sector_to_read=(entrynumber/16)-(clusters_to_read*(unsigned long)BPB_secperclus);
unsigned long entry_to_read=((entrynumber & 0x0000000F)*32);

//walk the cluster chain for the directory entry that we need...
    for(unsigned long m=0; m<clusters_to_read;m++){
      directory_previouscluster=directory_cluster;
      directory_cluster=readfat(directory_previouscluster);
      if ((directory_cluster & 0x0FFFFFFF)>0x0fffffef){
        return (0x02);
      }
    }
    directory_cluster -=2;
    directory_cluster *= (unsigned long)BPB_secperclus;
    directory_cluster+= BPB_firstdatasector;
    directory_cluster += sector_to_read;
    SD_buffer_block(directory_cluster); 
    for(int i=0;i<32;i++){
      directory_entry_buffer[i]=SDarray[entry_to_read+i];
    }		
    Serial.print("#");space();Serial.print(entrynumber,HEX);space();
    for(char i=0;i<32;i++){
      Serial.print(directory_entry_buffer[i],HEX);space();
    }
    Serial.println("_");
}



  
  
char get_long_file_name(unsigned long entry, char verbose){
  unsigned char i=0;
  read_directory_entry(entry--,0);
  if((directory_entry_buffer[0x0b]==0x0f)||(directory_entry_buffer[0] == 0xe5)||(directory_entry_buffer[0] == 0)){return 0x00;}
  unsigned char lfnchecksum=0;//for long filename checksum calculation. start with a zero.
  for (i = 0; i < 11; i++) {
    lfnchecksum = (((lfnchecksum & 1) << 7) | ((lfnchecksum & 0xfe) >> 1)) + directory_entry_buffer[i];
  }

  for (i = 0; i < 11;i++) {
      long_file_name[i]=0;
  }
  unsigned char shortenednameindex=0;
  for (i = 0; i < 8;i++) {
  if(directory_entry_buffer[i]!=' '){
      long_file_name[shortenednameindex++]=directory_entry_buffer[i];
    }
  }
  
  if(directory_entry_buffer[i]!=0x20){
    long_file_name[shortenednameindex++]='.';
    long_file_name[shortenednameindex++]=directory_entry_buffer[i++];
    long_file_name[shortenednameindex++]=directory_entry_buffer[i++];
    long_file_name[shortenednameindex++]=directory_entry_buffer[i++];
  }
  long_file_name[shortenednameindex]=NULL;
  i=0;
  do{
     read_directory_entry(entry--,0);

     if((directory_entry_buffer[13]==lfnchecksum)&&(directory_entry_buffer[0x0b]==0x0f)){
       long_file_name[i++]=(directory_entry_buffer[1]);
       long_file_name[i++]=(directory_entry_buffer[3]);
       long_file_name[i++]=(directory_entry_buffer[5]);
       long_file_name[i++]=(directory_entry_buffer[7]);
       long_file_name[i++]=(directory_entry_buffer[9]);
       long_file_name[i++]=(directory_entry_buffer[14]);
       long_file_name[i++]=(directory_entry_buffer[16]);
       long_file_name[i++]=(directory_entry_buffer[18]);
       long_file_name[i++]=(directory_entry_buffer[20]);
       long_file_name[i++]=(directory_entry_buffer[22]);
       long_file_name[i++]=(directory_entry_buffer[24]);
       long_file_name[i++]=(directory_entry_buffer[28]);
       long_file_name[i++]=(directory_entry_buffer[30]);
       long_file_name[i]=0;
     } 
  }while((i<MAXFILENAMELENGTH)&&
  (directory_entry_buffer[0x0b]==0x0f)&&
  (!(directory_entry_buffer[0x00]&0x40)));
  if(verbose){
    Serial.write(long_file_name);
  }
  return 1;
}

void find_bpb(){
unsigned long bigtemp;
unsigned long BPB_resvdseccnt=0;
unsigned int  BPB_start=0;
  SD_buffer_block(0);

  BPB_start=((unsigned long)SDarray[454]);
  BPB_start+=((unsigned long)SDarray[455]*256);
  SD_buffer_block((unsigned long)BPB_start);

  BPB_bytespersec=SDarray[0x0b];
  BPB_bytespersec+=((unsigned long)SDarray[0x0c]*256);
  BPB_secperclus=SDarray[0x0d];
  BPB_resvdseccnt=(unsigned long)SDarray[0x0e];
  BPB_resvdseccnt+=((unsigned long) SDarray[0x0f]*256);

  unsigned long BPB_numFATs=(unsigned long)SDarray[0x10];
//unsigned long BPB_RootEntCnt=(unsigned long)SDarray[0x11]+((unsigned long)SDarray[0x12]*0x100);

  unsigned long BPB_FATSz32=0;
  BPB_FATSz32=(unsigned long)SDarray[0x24];//RecSPI();
  BPB_FATSz32+=((unsigned long)SDarray[0x25]*0x100);  //36.37
  BPB_FATSz32+=((unsigned long)SDarray[0x26]*0x10000);//RecSPI();
  BPB_FATSz32+=((unsigned long)SDarray[0x27]*0x1000000);  //36.37.38.39

  BPB_rootclus=(unsigned long)SDarray[0x2c];  //44.45.46.47
  BPB_rootclus+=((unsigned long)SDarray[0x2d]*0x100);
  BPB_rootclus+=((unsigned long)SDarray[0x2e]*0x10000);
  BPB_rootclus+=((unsigned long)SDarray[0x2f]*0x1000000);
//  root_ccl=BPB_rootclus;

  BPB_fatstart=BPB_start+BPB_resvdseccnt;
  BPB_firstdatasector = BPB_start + BPB_resvdseccnt + (BPB_numFATs * BPB_FATSz32);// + RootDirSectors;
//  BPB_datsec = (long)BPB_start + (long)BPB_firstdatasector;
//  datsec = (unsigned long)BPB_start + (unsigned long)BPB_firstdatasector;
//  Serial.print("some info about card:");
//  Serial.print(" bpbst:"); Serial.println(BPB_start,DEC); 
  Serial.print("bpsec:"); Serial.println(BPB_bytespersec,DEC); 
  Serial.print("ScPeC:"); Serial.println(BPB_secperclus,DEC); 
//  Serial.print(" BPB_RsvdScCt:"); Serial.println(BPB_resvdseccnt,DEC); 
  Serial.print("NmFAT:"); Serial.println(BPB_numFATs,DEC); 
//  Serial.print(" fatstart:"); Serial.println(BPB_fatstart,HEX); 
//  Serial.print(" BPB_rootclus:"); Serial.println(BPB_rootclus,HEX); 
//  Serial.print(" FirstDataSector:"); Serial.println(BPB_firstdatasector,HEX);
//  Serial.print(" BPB_FATSz32:"); Serial.println(BPB_FATSz32,HEX);
}


void find_highest_entry_number(void){
  unsigned long clust_high;
  unsigned long eocmark;
  unsigned long root_ccl = cd_cluster[cd_depth]; //BPB_rootclus;
  unsigned long root_p_cl;
  clust_high = 0;
  do{
    root_p_cl=root_ccl;
    root_ccl=readfat(root_p_cl);
//    Serial.print("cluster seekB:");Serial.println(root_ccl,HEX);
    eocmark=root_ccl & 0x0FFFFFFF;
    clust_high++;
  }while(eocmark<0x0FFFFFEF);
  highestentry=clust_high * BPB_secperclus;
  highestentry=   highestentry*16;
  highestentry--;
//  Serial.print("highest possible directory entry (hex) is ");
  Serial.println(highestentry,HEX);
}


unsigned long readfat(unsigned long fatoffset){
unsigned int temp;
unsigned long tempb;
unsigned int los;
	temp=0;
	fatoffset=fatoffset*2;
	los = *(((unsigned char*)&fatoffset)+0);	//the bottom byte of the address goes directly to a word in the FAT
        los*=2;
	fatoffset=fatoffset / 256; 
	fatoffset+=BPB_fatstart;
	if(!SD_buffer_block(fatoffset)){
		Serial.println("fat buffering fail");
	}
	tempb = (unsigned long) SDarray[los];
	tempb += (unsigned int) SDarray[los+1]*0x100;
	tempb += (unsigned int) SDarray[los+2]*0x10000;
	tempb += (unsigned int) SDarray[los+3]*0x1000000;
	return tempb;
}


char read_sector_to_serial(unsigned long x){
unsigned long foo=0;
unsigned int foofoo=0;

  if(SD_buffer_block(x)){
    read_buffer_to_serial();
  }
}

void read_buffer_to_serial(void){
  
    for(unsigned int foo=0;foo<8;foo++){
      for(unsigned int foofoo=0;foofoo<64;foofoo++){
 //       Serial.print((foo*32)+foofoo,DEC);
 //       space();
        Serial.print(SDarray[(foo*64)+foofoo]);
//        printabyte(SDarray[(foo*32)+foofoo]);
      }
      Serial.println(" ");
    }
    Serial.println("--------------------------------");

}

/////////////////////////////
int read_sector_to_vs1011(long sector){
unsigned int bufferpointer=0; 
unsigned int ii=0;
  digitalWrite(VS1011_XDCS,1);
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(LED0,1);
  if(!SDHC){sector*=512;}
  fast_spi();
  SD_buffer_block(sector);
//read_buffer_to_serial();
  digitalWrite(LED0,0);
  digitalWrite(LED1,1);
  digitalWrite(VS1011_XDCS, 0);
  bufferpointer=0;
  for(unsigned char i=16;i>0;i--){
    while(digitalRead(VS1011_DREQ)==0){;}
    for(unsigned int ii=0;ii<32;ii++){
      NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();NOP();
      SPDR=SDarray[bufferpointer];
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
  slow_spi();
//  digitalWrite(VS1011_XDCS, 1);
  digitalWrite(VS1011_XCS, 0);
  SendRecSPI(a);
  SendRecSPI(b);
  temp = SendRecSPI(c);
  temp=temp*256;
  temp+=SendRecSPI(d);		
  digitalWrite(VS1011_XCS, 1);
  fast_spi();
  return temp;
}

//void set_volume( char l, char r){
//  VS_command(0x02,0x0b,255-l,255-r);
//}

void reset_vs1011_soft(char verbosity){
  VS_command(0x02,0x00,0x00,0x04);
  VS_command(0x02,0x00,0x08,0x00);
  VS_command(0x02,0x0b,255-volume_left,255-volume_right);
  if(verbosity==VERBOSE){
    Serial.print("Vs1011 volume register is: ");
    Serial.println(VS_command(0x03,0x0b,0xff,0xff), HEX);
  }
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(VS1011_XDCS, 1);
}

void reset_vs1011_hard(char verbosity){
  slow_spi();
  delay(5);
  digitalWrite(VS1011_XRESET, LOW);
  delay(1);
  digitalWrite(VS1011_XRESET, HIGH);
  delay(3);
  VS_command(0x02,0x00,0x00,0x04);
  VS_command(0x02,0x00,0x08,0x00);
  VS_command(0x02,0x0b,255-volume_left,255-volume_right);
  if(verbosity==VERBOSE){
    Serial.print("Vs1011 volume register is: ");
    Serial.println(VS_command(0x03,0x0b,0xff,0xff), HEX);
  }
  digitalWrite(VS1011_XCS, 1);
  digitalWrite(VS1011_XDCS, 1);
  fast_spi();

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
void SD_skip(int count){
	for (;count>0;count--){
		SendSPI(0xFF);
	}
}
////////////////////////////////////////////////////////////////////////////////////////////////

char SD_buffer_block(unsigned long block){
static unsigned long cached=0xffffffff;
  if(block==cached){return 1;}
  digitalWrite(LED2,HIGH);
  if(SD_open_block(block)){
    for(int x=0;x<512;x++){
      SDarray[x]=RecSPI();
    }
    SD_close_block();
    cached=block;
    digitalWrite(LED2,LOW);

    return 1;
  }
  SD_init(1);

  return 0;
}

unsigned char SD_open_block(unsigned long block_number){
//unsigned char tries=0;
unsigned char i=0;
  if(!SDHC){block_number*=512;}
  SendSPI(0xFF);
  SendSPI(0xFF);

//  waitNotBusy(100);
//  SendRecSPI(0xFF);
//  SendRecSPI(0xFF);
//  digitalWrite(SD_XCS,0);                     // set SD_XCS = 0 (on)
  if(SD_command(17,
  (*(((char*)&block_number)+3)),
  (*(((char*)&block_number)+2)),
  (*(((char*)&block_number)+1)),
  (*(((char*)&block_number)+0)),0xff)==0){
  if(waitStartBlock()) {return 1;}
    Serial.print("open fail FE"); 
    for(i=0;i<255;i++){
      SendSPI(0xFF);
      SendSPI(0xFF);
    }
  }

  Serial.print("open fail ZERO"); 
  digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
  SendRecSPI(0xFF);// give SD the clocks it needs to finish off
  SendRecSPI(0xFF);// give SD the clocks it needs to finish off
  return 0;
}


/** Wait for start block token */
unsigned char waitStartBlock(void) {
  uint16_t t0 = millis();
  unsigned char stat=0;
  while ((stat = RecSPI()) == 0XFF) {
    if (((uint16_t)millis() - t0) > 300) {
    Serial.print("fe timeout"); 
      digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
      return 0;
    }
  }
  if (stat != 0xFE) {
    Serial.print("fe fail"); 
    digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
    return 0;
  }
  return 1;
}


void SD_close_block(void){
  SendSPI(0xFF);                 // CRC bytes that are not needed
  SendSPI(0xFF);
  digitalWrite(SD_XCS,1);            // set SD_XCS = 1 (off)
  SendSPI(0xFF);                // give SD the clocks it needs to finish off
  SendSPI(0xff);
}


// wait for card to go not busy
int waitNotBusy(unsigned int timeoutMillis) {
  uint16_t t0 = millis();
  do {
    if (RecSPI() == 0XFF) return true;
  }
  while (((unsigned int)millis() - t0) < timeoutMillis);
  return false;
}


////////////////////////////////////////////////////////////////////////////////////////////////////
char SD_command(char command, char a, char b, char c, char d, char check){
unsigned char response=0;
  command |= 0b01000000;

// wait for card to go not busy
  digitalWrite(SD_XCS,0);
  waitNotBusy(50);

  SendSPI(command);
  SendSPI(a);
  SendSPI(b);
  SendSPI(c);
  SendSPI(d);
  SendSPI(check);
// for(char i = 0; i < 10; ++i){
//    response =   RecSPI();
//    Serial.print(command & 0b10111111,DEC); Serial.print(" SD_command loop returns: HEX> "); Serial.print(response,HEX); Serial.print("  BINARY> "); Serial.println(response,BIN);
//    if(response != 0xff){
//      return response;
//    }
//  }
  // wait for response
  for (unsigned char i = 0; ((response = RecSPI()) & 0X80) && i != 0XFF; i++){
//    delay(1000);
    //      Serial.print(command & 0b10111111,DEC);
    //    Serial.print(" SD_command loop returns: HEX> ");
   //     Serial.print(response,HEX);
   //     Serial.print("  BINARY> ");
    //    Serial.println(response,BIN);
  }
//  Serial.print(command & 0b10111111,DEC); Serial.print(" SD_command loop returns: HEX> "); Serial.print(response,HEX); Serial.print("  BINARY> "); Serial.println(response,BIN);

  return response;
}

/*  
void printabyte(unsigned char temp){
  Serial.print(temp);    
  Serial.print("--"); 
  Serial.print(temp,HEX);    
  Serial.print("-"); 
  Serial.println(temp,BIN);
}
*/



/** read CID or CSR register */
uint8_t readRegister(uint8_t cmd, void* buf) {
  uint8_t* dst = reinterpret_cast<uint8_t*>(buf);
  if (cardCommand(cmd, 0)) {
    error(SD_CARD_ERROR_READ_REG);
    goto fail;
  }
  if (!waitStartBlock()) goto fail;
  // transfer data
  for (uint16_t i = 0; i < 16; i++) dst[i] = spiRec();
  spiRec();  // get first crc byte
  spiRec();  // get second crc byte
  chipSelectHigh();
  return true;

 fail:
  chipSelectHigh();
  return false;
}

/**
 * Determine the size of an SD flash memory card.
 * \return The number of 512 byte data blocks in the card
 *         or zero if an error occurs.
 */

uint32_t cardSize(void) {
  csd_t csd;
  if (!readCSD(&csd)) return 0;
  if (csd.v1.csd_ver == 0) {
    uint8_t read_bl_len = csd.v1.read_bl_len;

    uint16_t c_size = (csd.v1.c_size_high << 10)
                      | (csd.v1.c_size_mid << 2) | csd.v1.c_size_low;

    uint8_t c_size_mult = (csd.v1.c_size_mult_high << 1)
                          | csd.v1.c_size_mult_low;
    return (uint32_t)(c_size + 1) << (c_size_mult + read_bl_len - 7);
  } else if (csd.v2.csd_ver == 1) {
    uint32_t c_size = ((uint32_t)csd.v2.c_size_high << 16)
                      | (csd.v2.c_size_mid << 8) | csd.v2.c_size_low;
    return (c_size + 1) << 10;
  } else {
    error(SD_CARD_ERROR_BAD_CSD);
    return 0;
  }
}



int SD_init(bool report){	//Initialises the SD into SPI mode and sets block size
//char p;

int i, ii, tries;
unsigned char n, cmd; 
unsigned char ocr[4]={0,0,0,0};
  
  SDHC=0;
  char SD2=0;

  slow_spi();
//  delay(30);	
  digitalWrite(SD_XCS,1);	// set SD_XCS = 1 (off)
//  delay(30);
  for(i=0;i<10;i++){SendSPI(0xFF);} // initialise the SD card into SPI mode by sending clks on
//  delay(1);
  digitalWrite(SD_XCS,0);				                     // set SD_XCS = 0 (on) tells card to go to spi mode when it receives reset

  for(i=0; i<100; i++){
    if(report){Serial.println("c0");}
    if(SD_command(0,0,0,0,0,0x95)==1){//
      if(report){Serial.println("good");}
      break;
    }
  }  
 
  if(SD_command(0x08, 0,0,0x01,0xaa,0x87)& 0x04){SD2=0;SDHC=0;} //0x04 is R1_ILLEGAL_COMMAND bit
  else{
    for (n = 0; n < 4; n++){ 
      ocr[n] = RecSPI(); 
      if(report){Serial.print("OCR"); space(); Serial.print(ocr[n],HEX); space();}
    } /* Get trailing return value of R7 resp */
    if (ocr[2] == 0x01 && ocr[3] == 0xAA) { /* The card can work at vdd range of 2.7-3.6V */
       SD2=1; if(report){Serial.println("'0,0,1,AA', SD v2");} //SDHC = 1 but it may be set back to 0 in the next test
    }else{
//      SDHC=0;
      if(report){Serial.println("SD1");}
    }
  }

//  Serial.print("SD2 <<6 is"); 
  Serial.println(SD2<<6,BIN);
  Serial.println(SD2<<6,HEX);


  do{
    if(report){Serial.println("c55");}
    SD_command(55,0,0,0,0,0xFF);//while(SD_response_masked(0b10000000)==0){
//  if(report){Serial.println("SD init: ACMD41...");}

    n= SD_command(41,SD2<<6,0,0,0,0xFF);//{
//      if(report){Serial.println("acmd41 returned nonzero!");}
    
  }while(n != 0);  

 // SendSPI(0xff);                // 
  
  if(SD2){
    if(report){Serial.println("SD2: c58");}
    if(SD_command (58, 0,0,0,0,0xff)){Serial.println("FAIL58"); return 0;}
    for (n = 0; n < 4; n++){ 
      ocr[n] = RecSPI(); 
      if(report){Serial.println(ocr[n],HEX);}
      if( (ocr[0] & 0xc0) ==0xc0){SDHC=1;}
    }
  }
  if(SDHC){Serial.println("SDHC!");}
  else{Serial.println("SD<2GB)!");}
  if(report){Serial.println("c16:");}
  SD_command(16,0,0,0x02,0,0xFF);       // block size command

  digitalWrite(SD_XCS,1);            //off
  fast_spi();
  return 1; //good
}

////////////////////////////////////////////////////////////////////////////////////////////////
/*
int SD_response(unsigned char response){	//reads the SD until we get the response we want or timeout
	for(int count=0;count<1000;count++){
		if(RecSPI() == response){
			return (1);
		}
	}
	return 0;
}
*/
void fast_spi(){
    SPCR = 0b01010000;  // interrupt disable, spi enabled, MSB first, Master mode, SCK low when idle, sample on rising SCK edge, fastest clock 
    SPSR |= (1 << SPI2X); //doubled clock frequency 
}
void slow_spi(){
    SPCR = 0b01010011;  // interrupt disable, spi enabled, MSB first, Master mode, SCK low when idle, sample on rising SCK edge, fastest clock 
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

static unsigned char RecSPI(void) {             // send one byte, get another in exchange
  SPDR = 0xff;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
  return SPDR;                             // SPIF will be cleared
}

static void SendSPI(unsigned char Dbyte) {             // send one byte, get another in exchange
  SPDR = Dbyte;                    // Start the transmission
  while (!(SPSR & (1<<SPIF))){;}     // Wait until the end of the transmission
}


//////////////////////////////////////////////////utility routines///////////////////////////////////////
void ledflash(int number, int duration) {  
  for(;number>0;number--){
 
    digitalWrite(RED, HIGH);   // sets the LED on  
    delay(duration/6);                  // waits  
    digitalWrite(RED, LOW);    // sets the LED off  

    digitalWrite(GREEN, HIGH);    // sets the LED off  
    delay(duration/6);                  // waits  
    digitalWrite(GREEN, LOW);   // sets the LED on  

    digitalWrite(BLUE, HIGH);   // sets the LED on  
      delay(duration/6);
    digitalWrite(BLUE, LOW);    // sets the LED off  
  }
} 

void space(void){
  Serial.print(" ");
}



