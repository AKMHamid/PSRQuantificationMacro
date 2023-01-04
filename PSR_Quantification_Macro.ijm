/* Author: Ahmad Kamal Hamid, Wagner group, Institute of Physiology, University of Zurich
 *  This macro is for artifact removal and quantification of Picrosirius Red-stained renal tissue imaged by brightfield microscopy (RGB with a white background)
 *  The code was developed for shade-corrected stitched images obtained by the Leica THUNDER Imaging System (20x obj) of paraffin-embedded 5-μm tissue slices 
 *  It was written on ImageJ 1.53t
 */
// Commands below prompt the user to select an input folder (of image files, e.g. tiff, dicom, fits, pgm, jpeg, bmp, gif) and output folder where measured images will be stored for later validation
inputDir=getDirectory("Select input folder");
outputDir=getDirectory("Select output folder");
// Obtaining first timestamp to eventually calculate runtime for the macro
TimeStamp1=getTime();
// Commands below initiate batching and a for loop that iterates through images in the input folder list while running the analysis
setBatchMode(true); 
image_list = getFileList(inputDir);
for (k=0; k<image_list.length; k++) {
	title = "[Progress]";
	run("Text Window...", "name="+ title +" width=30 height=2 monospaced");
// The for loop below codes for a progress bar for the processing
	for (k=0; k<image_list.length; k++) {
		print(title, "\\Update:"+k+"/"+image_list.length+" ("+(k*100)/image_list.length+"%)\n"+getBar(k, image_list.length));
		open(inputDir+image_list[k]);
/* Command below replaces all black pixels with white, this is relevant in stitched images where background may be white while canvas (signal absence) is black
 * If this command is problematic (e.g. dead pixels within the tissue due to camera sensor issues), it can be replaced with a floodFill tool that targets corners
 * This assumes that the canvas in the corners of the stitched image, which is not always the case!
 * 		w=getWidth();
		h=getHeight();
		setForegroundColor(255, 255, 255);
		floodFill(0, 0);
		floodFill(w-1, 0);
		floodFill(w-1, h-1);
		floodFill(0, h-1);
 */
		changeValues(0x000000,0x000000,0xffffff);
// Commands below set variables ImageTitle for later reference and the center coordinates of the rectangular image for autoselection later
		ImageTitle=getTitle();
		CentroidX=getValue("X");
		CentroidY=getValue("Y");
		run("Duplicate...", "title=Original");
		run("Duplicate...", "title=Original2");
		run("Duplicate...", "title=Original3");
		run("Duplicate...", "title=BGRemoval");
// Commands below Gaussian blur the tissue area to create a perimeter around it for subsequent deletion of the surrounding area
		setOption("BlackBackground", true);
		run("Convert to Mask");
		run("Duplicate...", "title=TotalSignal");
		selectWindow("BGRemoval");
		run("Gaussian Blur...", "sigma=100");
		run("Convert to Mask");
		run("Fill Holes");
/* The command below automates the selection process for tissue delineation. For manual selection, replace the doWand command with the one below. This can only be done with batch mode set to false
 * NOTE: Turning off batch mode would substantially slow down the computation!
 * {waitForUser("Please click the white ROI \n\nThen click OK");
   };
 */
		setTool("wand");
		run("Select None");
		doWand(CentroidX, CentroidY);
		run("Make Inverse");
		setBackgroundColor(0, 0, 0);
		selectWindow("Original");
		run("Restore Selection");
		run("Clear", "slice");
		run("Invert");
		run("Select None");
// The code segment below was autogenerated by Fiji. To adjust in a more user-friendly interface: Image > Adjust > Color Threshold > ... > Macro
// Color Thresholder 2.1.0/1.53c
// Autogenerated macro, single images only!
// Colour Thresholding-------------START
		min=newArray(3);
		max=newArray(3);
		filter=newArray(3);
		a=getTitle();
		run("HSB Stack");
		run("Convert Stack to Images");
		selectWindow("Hue");
		rename("0");
		selectWindow("Saturation");
		rename("1");
		selectWindow("Brightness");
		rename("2");
		min[0]=240;
		max[0]=255;
		filter[0]="pass";
		min[1]=100;
		max[1]=255;
		filter[1]="pass";
		min[2]=0;
		max[2]=255;
		filter[2]="pass";
		for (i=0;i<3;i++){
		  selectWindow(""+i);
		  setThreshold(min[i], max[i]);
		  run("Convert to Mask");
		  if (filter[i]=="stop")  run("Invert");
		}
		imageCalculator("AND create", "0","1");
		imageCalculator("AND create", "Result of 0","2");
		for (i=0;i<3;i++){
		  selectWindow(""+i);
		  close();
		}
		selectWindow("Result of 0");
		close();
		selectWindow("Result of Result of 0");
		rename(a);
// Colour Thresholding-------------END
		rename("ColorThresholded");
		run("Invert");
// Commands below create a mask from the green channel of the original RGB image to exclude artifacts of excessive signal strength, e.g. perivascular collagen
		selectWindow("Original2");
		run("Split Channels");
		selectWindow("Original2 (blue)");
		close();
		selectWindow("Original2 (red)");
		close();
		selectWindow("BGRemoval");
		selectWindow("Original2 (green)");
		run("Invert");
		run("Restore Selection");
		run("Clear", "slice");
		run("Select None");
		run("Duplicate...", "title=ArtifactRemoval");
		setAutoThreshold("Default dark");
		setThreshold(200, 255);
		run("Convert to Mask");
		run("Gaussian Blur...", "sigma=150");
		run("Convert to Mask");
		run("Fill Holes");
		run("Analyze Particles...", "size=100000-Infinity pixel show=Masks");
// Commands below remove the artifacts from the color-thresholded image by adding the mask from the previous step
		imageCalculator("Add create", "ColorThresholded","Mask of ArtifactRemoval");
		selectWindow("Result of ColorThresholded");
		run("Invert");
		run("Restore Selection");
		run("Make Inverse");
// Commands below debinarizes the cleaned-up color-thresholded image by replacing the white pixels with the grayscale saturation value of the original image
		selectWindow("BGRemoval");
		selectWindow("Original3");
		run("Restore Selection");
		run("Clear", "slice");
		run("Invert");
		run("Select None");
		run("HSB Stack");
		run("Stack to Images");
		selectWindow("Hue");
		close();
		selectWindow("Brightness");
		close();
		selectWindow("Saturation");
		selectWindow("Result of ColorThresholded");
		run("Divide...", "value=255");
		imageCalculator("Multiply create", "Result of ColorThresholded","Saturation");
		rename("Grayscale PSR Signal");
		run("Restore Selection");
// Command below sets the measurement parameters. This can be adjusted depending on the intended downstream calculation. As is, the RawIntDen can be used to backcalculate pixel count (i.e. dividing by 255 for total tissue). 
		run("Set Measurements...", "integrated display redirect=None decimal=3");
// Commands below generate a binary image where non-tissue, large lumens and spaces, and previously defined artifacts are black, this will be used for normalizing the PSR signal
		selectWindow("BGRemoval");
		selectWindow("TotalSignal");
		run("Restore Selection");
		run("Clear", "slice");
		run("Select None");
		run("Invert");
		imageCalculator("Add create", "TotalSignal","Mask of ArtifactRemoval");
		selectWindow("Grayscale PSR Signal");
		saveAs("Tiff", outputDir+"Grayscale_PSR_Signal_"+image_list[k]);
		run("Measure");
		selectWindow("Result of TotalSignal");
		run("Invert");
		run("Restore Selection");
		saveAs("Tiff", outputDir+"Total_Tissue_"+image_list[k]);
		run("Measure");
 		close("*");
 	}
 // Below is the continuation of the progress bar for loop initiated above
 	print(title, "\\Close");
 	function getBar(p1, p2) {
        n = 20;
        bar1 = "--------------------";
        bar2 = "********************";
        index = round(n*(p1/p2));
        if (index<1) index = 1;
        if (index>n-1) index = n-1;
        return substring(bar2, 0, index) + substring(bar1, index+1, n);
	}
}	
saveAs("Results",outputDir+"PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
// Elapsed time and time per image
TimeStamp2=getTime();
ElapsedTimeMS=TimeStamp2-TimeStamp1
	if (ElapsedTimeMS<60000) {
		ElapsedTime=d2s(ElapsedTimeMS/1000, 0);
		TimeUnit="sec";
	}
	if (ElapsedTimeMS>60000) {
		ElapsedTime=d2s(ElapsedTimeMS/60000, 1);
		TimeUnit="min";
	}
	if (ElapsedTimeMS>3600000) {
		ElapsedTime=d2s(ElapsedTimeMS/3600000, 2);
		TimeUnit="hr";
	}
TimePerImage=d2s((ElapsedTimeMS/1000)/image_list.length, 2);
setBatchMode(false);
waitForUser("Done!", image_list.length+" images have been processed, and the output images and results have been saved to the indicated directory at:\n\n"+outputDir+"\n Elapsed time = "+ElapsedTime+" "+TimeUnit+"\n On average, "+TimePerImage+" sec/image");
