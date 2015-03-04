/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
* 
* Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
*
* This program is free software; you can redistribute it and/or modify it under the
* terms of the GNU Lesser General Public License as published by the Free Software
* Foundation; either version 3.0 of the License, or (at your option) any later
* version.
* 
* BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
* WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
* PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public License along
* with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
*
*/
package org.bigbluebutton.voiceconf.sip;

import org.slf4j.Logger;
import org.red5.logging.Red5LoggerFactory;

public class ConferenceProvider {

	private static Logger log = Red5LoggerFactory.getLogger(CallAgent.class, "sip");

	private final String host;
	private final int sipPort;

	private final int startAudioPort;
	private final int stopAudioPort;
	private final int startVideoPort;
	private final int stopVideoPort;

	private int curAvailableAudioPort;
	private int curAvailableVideoPort;
	
	public ConferenceProvider(String host, int sipPort, int startAudioPort, int stopAudioPort, int startVideoPort, int stopVideoPort) {
		this.host = host;
		this.sipPort = sipPort;

		this.startAudioPort = startAudioPort;
		this.stopAudioPort = stopAudioPort;
		this.startVideoPort = startVideoPort;
		this.stopVideoPort = stopVideoPort;

		curAvailableAudioPort = startAudioPort;
		curAvailableVideoPort = startVideoPort;
	}
	
	public int getFreeAudioPort() {
    	synchronized(this) {
        	int availablePort = curAvailableAudioPort;
        	curAvailableAudioPort++;
    		if (curAvailableAudioPort > stopAudioPort) curAvailableAudioPort = startAudioPort; 

    		log.debug("ConferenceProvider => Getting free AUDIO port: " + availablePort);   
    		return availablePort;
    	}
    }

	public int getFreeVideoPort() {
    	synchronized(this) {
        	int availablePort = curAvailableVideoPort;
        	curAvailableVideoPort++;
    		if (curAvailableVideoPort > stopVideoPort) curAvailableVideoPort = startVideoPort;  

    		log.debug("ConferenceProvider => Getting free VIDEO port: " + availablePort);   
    		return availablePort;
    	}
    }    
	
	public String getHost() {
		return host;
	}
	
	public int getStartAudioPort() {
		return startAudioPort;
	}
	
	public int getStopAudioPort() {
		return stopAudioPort;
	}

	public int getStartVideoPort() {
		return startVideoPort;
	}
	
	public int getStopVideoPort() {
		return stopVideoPort;
	}
}