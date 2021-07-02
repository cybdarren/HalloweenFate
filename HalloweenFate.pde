
import gohai.glvideo.*;
import deadpixel.keystone.*;
import processing.sound.*;
import processing.io.*;

Keystone ks;
CornerPinSurface surface;
GLMovie mov;
PGraphics offscreen;
SoundFile soundWraith;
SoundFile soundCreak;
PCA9685 servos;
float servo_angle = 0.0; // current angle for the servo
float servo_step = 0.0; // angle step per millisecond for the given sound sample duration
float moveStartTime = 0.0;

boolean startSequence = false;

static float retriggerDelayMS = 10000.0; 

// states for the box
enum State {
  IDLE,
  BOX_CLOSED,
  BOX_OPENING,
  BOX_OPEN,
  BOX_CLOSING,
  BOX_RETRIGGER_DELAY
}

// current state
State currentState = State.BOX_CLOSED;

void setup() {
  // Keystone will only work with P3D or OPENGL renderers, 
  // since it relies on texture mapping to deform
  //size(854, 480, P3D);
  fullScreen(P3D);

  // load the soundfile and the movie (for some reason audio from the movie doesn't work
  soundWraith = new SoundFile(this, "H4-1.wav");
  soundWraith.stop();
  soundWraith.cue(0);
  soundCreak = new SoundFile(this, "creaky_door.wav");
  
  
  mov = new GLMovie(this, "H4-1.mkv");
  mov.pause();
  mov.jump(0);
  int mWidth = mov.width();
  int mHeight = mov.height();
  println("Movie has dimensions: " + mWidth + "x" + mHeight);

  // create the mapping surface,same size as the movie
  ks = new Keystone(this);
  surface = ks.createCornerPinSurface(mWidth, mHeight, 10);
  
  // attempt to load the configuration if it exists
  File configFile = new File(sketchPath() + "/keystone.xml");
  if (configFile.isFile()) {
    println("Found config file: " + configFile.getName());
    ks.load();
  }
  
  // We need an offscreen buffer to draw the surface we
  // want projected
  // note that we're matching the resolution of the
  // CornerPinSurface.
  offscreen = createGraphics(mWidth, mHeight, P2D);
  
  // attach to the box opening servo
  servos = new PCA9685("i2c-1", 0x40);
  servos.attach(0, 500, 2500);
  
  // this is assigned previously anyway
  currentState = State.BOX_CLOSED;
  
  // setup the GPIO
  GPIO.pinMode(4, GPIO.INPUT);
//  GPIO.attachInterrupt(4, this, "pinEvent", GPIO.RISING);
}

void draw() {
  // ensure the movie is played as a priority
  if (mov.available()) {
    mov.read();
    // Draw the movie on the offscreen surface
    offscreen.beginDraw();
    offscreen.image(mov, 0, 0);
    offscreen.endDraw();
  }

  // most likely, you'll want a black background to minimize
  // bleeding around your projection area
  background(0);
 
  // render the scene, transformed using the corner pin surface
  surface.render(offscreen);
  
  // test the GPIO trigger
  if (GPIO.digitalRead(4) == GPIO.HIGH) {
    startSequence = true;
  }
  
  // execute the state machine
  State nextState = State.IDLE;
  switch (currentState) {
    case BOX_CLOSED:
      nextState = execBOX_CLOSED();
      break;
    case BOX_OPENING:
      nextState = execBOX_OPENING();
      break;
    case BOX_OPEN:
      nextState= execBOX_OPEN();
      break;
    case BOX_CLOSING:
      nextState = execBOX_CLOSING();
      break;
    case BOX_RETRIGGER_DELAY:
      nextState = execBOX_RETRIGGER_DELAY();
      break;
    default:
      startSequence = false;
      nextState = State.BOX_CLOSED;
      break;
  }
  
  currentState = nextState;
}

State execBOX_CLOSED() {
  // check if any motion is seen on the PIR
  if (startSequence == true) {
    println("CLOSED -> OPENING");
    // start the creaking sound
    servo_angle = 0.0;
    soundCreak.cue(0);
    soundCreak.amp(0.6);
    float soundDuration = soundCreak.duration() * 1000.0; // convert to ms
    servo_step = 180.0 / soundDuration;
    moveStartTime = millis(); // start time
    
    soundCreak.play();
    return State.BOX_OPENING;
  }

  return State.BOX_CLOSED;
}

State execBOX_OPENING() {
  // get the current time into the servo move
  float currentTime = millis() - moveStartTime;
  servo_angle = servo_step * currentTime;

  if (servo_angle >= 180.0) {
    setServo(0, 180.0);
    
    // start the movie
    playMovie();
    delay(50);  // short delay to ensure movie starts
    println("OPENING -> OPEN");
    return State.BOX_OPEN;
  }
  
  setServo(0, servo_angle);
  return State.BOX_OPENING;
}

State execBOX_OPEN() {
  if (mov.playing()) {
    return State.BOX_OPEN;
  }
      
  // start the creaking sound
  servo_angle = 10.0;
  soundCreak.cue(0);
  soundCreak.amp(0.6);
  float soundDuration = soundCreak.duration() * 1000.0; // convert to ms
  servo_step = 180.0 / soundDuration; 
  moveStartTime = millis(); // start time  
  soundCreak.play();
  println("OPEN -> CLOSING");
  return State.BOX_CLOSING;
}

State execBOX_CLOSING() {
  // get the current time into the servo move
  float currentTime = millis() - moveStartTime;
  servo_angle = 180.0 - (servo_step * currentTime);

  if (servo_angle <= 0.0) {
    setServo(0, 0.0);
    println("CLOSING -> RETRIGGER_DELAY");
    // reuse the moveTimer for the delay
    moveStartTime = millis();
    return State.BOX_RETRIGGER_DELAY;
  }
  
  setServo(0, servo_angle);
  return State.BOX_CLOSING;
}

State execBOX_RETRIGGER_DELAY() {
  // get the delay
  float elapsedDelay = millis() - moveStartTime;
  
  if (elapsedDelay > retriggerDelayMS) {
    startSequence = false;
    println("RETRIGGER_DELAY -> BOX_CLOSED");
    return State.BOX_CLOSED; 
  }
    
  return State.BOX_RETRIGGER_DELAY;
}

void playMovie() {
  // reset the movie and audio to the start
  if (!mov.playing()) {
    mov.noLoop();
    mov.jump(0);
    soundWraith.cue(0);
    soundWraith.amp(1.0);
    
    // start both playing
    mov.play();
    soundWraith.play();
  }
}

void setServo(int servo, float angle) {
  servos.write(servo, angle);
}

//void pinEvent(int pin)
//{
//  println("Detected motion");
//  startSequence = true;
//}

void keyReleased() {
  switch(key) {
  case 'u':
    // open the box
    setServo(0, 180);
    break;
    
  case 'd':
    // close the box
    setServo(0, 0);
    break;
    
  case 'm':
    // play the sequence
    startSequence = true;
    break;
    
  case 'p':
    // play movie and audio
    playMovie();
    break;
    
  case 'q':
    println("Exiting");
    exit();
    break;
    
  case 'c':
    // enter/leave calibration mode, where surfaces can be warped 
    // and moved
    ks.toggleCalibration();
    break;

  case 'l':
    // loads the saved layout
    ks.load();
    break;

  case 's':
    // saves the layout
    ks.save();
    break;
  }
}

//clean up
void dispose() {
  mov.pause();
  mov.close();
  soundWraith.stop();
  soundCreak.stop();
  servos.detach(0);
  servos.close();
  super.dispose();
}
