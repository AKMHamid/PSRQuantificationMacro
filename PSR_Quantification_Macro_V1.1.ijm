/* Author: Ahmad Kamal Hamid, Wagner group, Institute of Physiology, University of Zurich
 * Tool: Renal Picrosirius Red Stain Quantification Macro v1.1, 10/05/2024
 *  This macro is for artifact removal and quantification of Picrosirius Red-stained renal tissue imaged by brightfield microscopy (RGB with a white background)
 *  The code was developed for shade-corrected stitched images obtained by the Leica THUNDER Imaging System (20x obj) of paraffin-embedded 5-μm tissue slices 
 *  It was initially written on ImageJ 1.53t but this version, 1.1, released on 10/05/2024, was tested on FIJI ImageJ 1.54f.
 *  Changes include:
 *  	Increased customization in GUI (manual canvas recoloring option, manual tissue selection option, size and intensity threshold customization, enabling intermediate export, enabling subset input)
 *  	Improved robustness (added numerous checkpoints and sanity checks, shifted to using ROI manager for restoring selections, removed scale and restored it prior to measuring, implemented protection of intermediate CSV file)
 *  	Improved data structuring (improved file naming, output subfolders implemented, added export of parameters used)
 *  	Improved efficiency and memory management (removed redundant commands)
 *  
 */
 
// Functions
// Function for progress bar
function getBar(p1, p2) {
	n = 20;
	bar1 = "--------------------";
	bar2 = "********************";
	index = round(n * (p1 / p2));
	if (index < 1) index = 1;
	if (index > n-1) index = n - 1;
	return substring(bar2, 0, index) + substring(bar1, index + 1, n);
}

//  Function to check pixel value, then flood fill if zero
function cornerFill(xcoord, ycoord) {
	pixelVal = getValue(xcoord, ycoord);
	if (pixelVal == 0) {
		floodFill(xcoord, ycoord);
	}
}

// Function to check if an array contains a value
function contains(array, value) {
		for (i = 0; i < array.length; i++) {
			if (array[i] == value) {
				return true;
			}
		}
		return false;
}

// Function to check if directory exists and creates it if false
function safeMakeDir(newDir) {
		if (!File.isDirectory(newDir)) {
			File.makeDirectory(newDir);
		}
}

// Prep
run("Fresh Start");
if (isOpen("Progress")) {
	selectWindow("Progress");
	run("Close");
}
 
// GUI choice lists
canvasChoices = newArray("Keep canvas color", "Change canvas to white at corners", "Change black pixels to white", "Manually color canvas");

// GUI
Dialog.create("PSR Quantification Macro");
	Dialog.addDirectory("Input directory (must contain image files only)", "/path/") // Input directory (image-only folder)
	Dialog.addString("Index (starting from 1) of specific images to run (e.g. 1, 4-7, 2, 10-12)", "All", 33);
	Dialog.addDirectory("Output directory", "/path/") // Output export directory
	Dialog.addRadioButtonGroup("Canvas processing", canvasChoices, 3, 4, canvasChoices[2]); 
	/* Provides option on dealing with canvas. 
	 * Option 1: canvas color = BG color. No processing needed.
	 * Option 2: flood fill all corners to white (assumes canvas ALWAYS at corners). 
	 * Option 3: changes all black pixels to white (assumes no dead pixels).
	 */
	Dialog.addCheckbox("Enable automated tissue tracing", true); // If enabled, a trace selection will be made by simulating a click with the wand tool at the center of the image. Assumed centered single-object tissue. 
	Dialog.addNumber("Tissue detection Gaussian blur, Sigma =", 100); // Radius (sigma) of Gaussian blur when detecting tissue
	Dialog.addMessage("PSR semantic segmentation parameters:", 12, "Blue");
	Dialog.addSlider("Hue bandpass filter lower threshold", 0, 255, 240); // Colorthresholding hue parameter
	Dialog.addSlider("Hue bandpass filter upper threshold", 0, 255, 255); // Colorthresholding hue parameter
	Dialog.addSlider("Saturation bandpass filter lower threshold", 0, 255, 100); // Colorthresholding saturation parameter
	Dialog.addSlider("Saturation bandpass filter upper threshold", 0, 255, 255); // Colorthresholding saturation parameter
	Dialog.addSlider("Brightness bandpass filter lower threshold", 0, 255, 0); // Colorthresholding brightness parameter
	Dialog.addSlider("Brightness bandpass filter upper threshold", 0, 255, 255); // Colorthresholding brightness parameter
	Dialog.addMessage("Artifact detection parameters:", 12, "Blue");
	Dialog.addSlider("Green channel lower threshold:", 0, 255, 200); // Artifact min green threshold
	Dialog.addSlider("Green channel upper threshold:", 0, 255, 255); // Artifact max green threshold
	Dialog.addNumber("Artifact detection Gaussian blur, Sigma =", 150); // Radius (sigma) of Gaussian blur when detecting artifacts
	Dialog.addNumber("Artifact post-blurring minimum size (px)", 100000); // Minimum size to accept as threshold (post blurring)
	Dialog.addCheckbox("Enable intermediate export of data (iteratively overwritten)", true); // Option to export data after every image. Please note that this requires overwriting, i.e. do NOT open the CSV file while the macro is running.


	Dialog.show();
	// Fetching user input
	inputDir = Dialog.getString();
	imgs2Process = Dialog.getString();
	outputDir = Dialog.getString();
	canvasProcessingApproach = Dialog.getRadioButton();
	autoTrace = Dialog.getCheckbox();
	tissueGaussianSigma = Dialog.getNumber();
	hueLower = Dialog.getNumber();
	hueUpper = Dialog.getNumber();
	satLower = Dialog.getNumber();
	satUpper = Dialog.getNumber();
	briLower = Dialog.getNumber();
	briUpper = Dialog.getNumber();
	artifactLower = Dialog.getNumber();
	artifactUpper = Dialog.getNumber();
	artifactGaussianSigma = Dialog.getNumber();
	artifactMinSize = Dialog.getNumber();
	intermediateExport = Dialog.getCheckbox();
	
// Obtaining first timestamp to eventually calculate runtime for the macro
timeStamp1 = getTime();

// Handling image subset if requested
imgList = getFileList(inputDir);
if (imgs2Process == "All" || imgs2Process == "all") {
	// Creating dummy index array with all indices available
    imgSubsetIndexArray = Array.getSequence(imgList.length);	
} else {
	imgSubsetInput = split(imgs2Process, ",");
	singleImgsArray = newArray(0);
	imgRangesArray = newArray(0);
	for (z = 0; z < imgSubsetInput.length; z++) {
		if (indexOf(imgSubsetInput[z], "-") == -1) {
			// Appending single image indices to array
			singleImgsArray[singleImgsArray.length] = parseFloat(imgSubsetInput[z]);
		} else {
			// Extracting single image indices from ranges and appending to array
			rangeLimitsArray = split(imgSubsetInput[z], "-");
			rangeArray = newArray(parseFloat(rangeLimitsArray[1]) - parseFloat(rangeLimitsArray[0]) + 1);
			for (zz = 0; zz < rangeArray.length; zz++) {
				imgRangesArray[imgRangesArray.length] = parseFloat(rangeLimitsArray[0]) + zz;
			}	
		}	
	}
	// Concatenating arrays 1 and 2 and sorting
	imgSubsetIndexArray = Array.concat(singleImgsArray, imgRangesArray);
	Array.sort(imgSubsetIndexArray);
	
	// Converting to indices starting from 0
	for (index = 0; index < imgSubsetIndexArray.length; index++) {
	    if (imgSubsetIndexArray[index] < 0) {
	      exit("Error: You selected an image range that includes values less than or equal to 0. Minimum accepted value is 1.");
	  	} else {
	      imgSubsetIndexArray[index] -= 1;
		}
	}
}

// Creating subfolders for export
totalTissueDir = outputDir + "Total tissue binary images" + File.separator;
safeMakeDir(totalTissueDir);

PSRImgDir = outputDir + "PSR grayscale images" + File.separator;
safeMakeDir(PSRImgDir);

dataDir = outputDir + "Data" + File.separator;
safeMakeDir(dataDir);

// Initiating batch mode and a for loop that iterates through images in the input folder list while running the analysis
setBatchMode(true); 

for (k = 0; k < imgSubsetIndexArray.length; k++) {
	progBarTitle = "[Progress]";
	run("Text Window...", "name=" + progBarTitle + " width=30 height=2 monospaced");
	
// The for loop below codes for a progress bar for the processing
	for (k = 0; k < imgSubsetIndexArray.length; k++) {
		print(progBarTitle, "\\Update:" + k + "/" + imgSubsetIndexArray.length + " ("+ (k * 100) / imgSubsetIndexArray.length + "%)\n" + getBar(k, imgSubsetIndexArray.length));
		// Protecting previous intermediate export if from another run to prevent overwritting in case of re-runs for image subsets
		tempFileList = getFileList(dataDir);
		if (k == 0 && contains(tempFileList, "IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV")) {
			lastMod = File.dateLastModified(dataDir + "IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
			lastModSplit = split(lastMod, " ");
			lastModTimeSplit = split(lastModSplit[3], ":");
			// Creating month string and integer arrays
			monthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
			monthNumbers = Array.getSequence(13); 
			// Converting month string to integer
			for (m = 0; m < monthNames.length; m++) {
				if (lastModSplit[1] == monthNames[m]) {
					lastModMonth = IJ.pad(monthNumbers[m] + 1, 2);
				}
			}
			// Renaming file with leading signature (last modification date and time)
			File.rename(dataDir + "IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV", dataDir +
				lastModSplit[5] + lastModMonth + lastModSplit[2] + "_" + lastModTimeSplit[0] + "-" + lastModTimeSplit[1] +
				"-" + lastModTimeSplit[2] + "_" + "_IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
			// File renaming command typically prints boolean completion in log, closing log
			if (isOpen("Log")) {
				selectWindow("Log");
				run("Close");
			}
		}
		// Opening image
		open(inputDir + imgList[imgSubsetIndexArray[k]]);

/* Commands below carry out canvas processing depending on user input in GUI which may be relevant for stitched images where background may be white while canvas (signal absence) is black.
 * Either uses a floodFill tool that targets corners changing color to white based on connectivity or replaces all black pixels with white in the entire image.
 * Option 1 is not recommended unless it is certainly known that canvas only occurs in corners, option 2 is not recommended if the camera has dead pixels or black pixels within the tissue.
 * Option 3 allows for the manual coloring in: the user simply clicks where the canvas regions are and it recolors them as white.
 */
 		if (canvasProcessingApproach == canvasChoices[1]) {
 			w = getWidth();
			h = getHeight();
			setForegroundColor(255, 255, 255);
			cornerFill(0, 0);
			cornerFill(w-1, 0);
			cornerFill(w-1, h-1);
			cornerFill(0, h-1);
 		} else if (canvasProcessingApproach == canvasChoices[2]) {
			changeValues(0x000000,0x000000,0xffffff);
 		} else if (canvasProcessingApproach == canvasChoices[3]) {
			setForegroundColor(255, 255, 255);
 			setTool("Flood Fill Tool");
 			setBatchMode("show");
 			waitForUser("User input required", "Please click on canvas regions to color them as white then click OK.");
 			setBatchMode("hide");
 		}

// Prepping for analysis: removing and storing scale information, assigning variables for center coordinates of the rectangular image for autoselection later, making image copies for processing
		getPixelSize(scaleUnit, pixelWidth, pixelHeight); // Fetching original scale
		Image.removeScale(); // Removing scale to simplify downstream operations
		CentroidX = getValue("X");
		CentroidY = getValue("Y");
		rename("Original0");
		run("Duplicate...", "title=Original1");
		run("Duplicate...", "title=BGRemoval");
		
// Running a Gaussian blur on the tissue area to create a perimeter around it for subsequent deletion of the surrounding area
		setOption("BlackBackground", true);
		run("Convert to Mask");
		run("Duplicate...", "title=TotalSignal");
		selectWindow("BGRemoval");
		run("Gaussian Blur...", "sigma=" + tissueGaussianSigma);
		run("Convert to Mask");
		run("Fill Holes");
// Automatic or manual delineation the tissue or allow for its selection 
 		setTool("wand");
		run("Select None");
 		if (autoTrace) {
			doWand(CentroidX, CentroidY);
 		} else {
 			setBatchMode("show");
 			counter = 0;
 			while (true) {
 				waitForUser("User input required", "Please click on the white object. \n\nThen click OK.");
 				if (selectionType() != -1) {
 					break;
 				} else {
 					counter += 1;
 					if (counter <= 2) {
						waitForUser("Error", "No selection was made, please try again.");
 					} else {
						exit("Error: No selection has been made. Timed out, aborting macro.");
 					}
 				}
 			}
 			setBatchMode("hide");
 		}
 		roiManager("add"); // Tissue ROI
 		run("Make Inverse");
 		roiManager("add"); // Non-tissue ROI
 		close("BGRemoval");
		selectWindow("Original0");
		roiManager("select", 1);
		run("Clear", "slice");
		run("Invert");
		run("Select None");

// The code segment below was autogenerated by Fiji for the semantic segmentation of the PSR stain. To adjust in a more user-friendly interface: Image > Adjust > Color Threshold > ... > Macro
// Color Thresholder 2.1.0/1.53c
// Autogenerated macro, single images only!
// Colour Thresholding-------------START
		min = newArray(3);
		max = newArray(3);
		filter = newArray(3);
		a = getTitle();
		run("HSB Stack");
		run("Convert Stack to Images");
		selectWindow("Hue");
		rename("0");
		selectWindow("Saturation");
		// Creating a copy so the saturation map is used in the later debinarization step
		run("Duplicate...", "title=1");
		selectWindow("Brightness");
		rename("2");
		min[0] = hueLower;
		max[0] = hueUpper;
		filter[0] = "pass";
		min[1] = satLower;
		max[1] = satUpper;
		filter[1] = "pass";
		min[2] = briLower;
		max[2] = briUpper;
		filter[2] = "pass";
		for (i = 0; i < 3; i++){
		  selectWindow("" + i);
		  setThreshold(min[i], max[i]);
		  run("Convert to Mask");
		  if (filter[i] == "stop")  run("Invert");
		}
		imageCalculator("AND create", "0","1");
		imageCalculator("AND create", "Result of 0","2");
		for (i = 0; i < 3; i++){
		  selectWindow("" + i);
		  close();
		}
		selectWindow("Result of 0");
		close();
		selectWindow("Result of Result of 0");
		rename(a);
// Colour Thresholding-------------END
		rename("ColorThresholded");
		run("Invert");

// Creating a mask from the green channel of the original RGB image to exclude artifacts of excessive signal strength, e.g. perivascular collagen
		selectWindow("Original1");
		run("Split Channels");
		close("Original1 (blue)");
		close("Original1 (red)");
		selectWindow("Original1 (green)");
		run("Invert");
		roiManager("select", 1);
		run("Clear", "slice");
		run("Select None");
		rename("ArtifactRemoval");
		setAutoThreshold("Default dark");
		setThreshold(artifactLower, artifactUpper);
		run("Convert to Mask");
		run("Gaussian Blur...", "sigma=" + artifactGaussianSigma);
		run("Convert to Mask");
		run("Fill Holes");
		run("Analyze Particles...", "size=" + artifactMinSize + "-Infinity pixel show=Masks");
		close("ArtifactRemoval");
// Removing the artifacts from the color-thresholded PSR image by adding the mask from the previous step
		imageCalculator("Add", "ColorThresholded","Mask of ArtifactRemoval");
		selectWindow("ColorThresholded");
		run("Invert");
		roiManager("select", 0);
// Debinarizing the cleaned-up color-thresholded image by replacing the white pixels with the grayscale saturation value of the original image
		// Normalizing the color thresholded
		selectWindow("ColorThresholded");
		run("Divide...", "value=255");
		imageCalculator("Multiply", "ColorThresholded","Saturation");
		close("Saturation");
		selectWindow("ColorThresholded");
		rename("Grayscale PSR Signal");
		roiManager("select", 0);
// Setting the measurement parameters. This can be adjusted depending on the intended downstream calculation. As is, the RawIntDen can be used to backcalculate pixel count (i.e. dividing by 255 for total tissue)
		run("Set Measurements...", "integrated display redirect=None decimal=3");
// Generating a binary image where non-tissue, large lumens and spaces, and previously defined artifacts are black, this will be used for normalizing the PSR signal
		selectWindow("TotalSignal");
		roiManager("select", 1);
		run("Clear", "slice");
		run("Select None");
		run("Invert");
		imageCalculator("Add", "TotalSignal","Mask of ArtifactRemoval");
		close("Mask of ArtifactRemoval");
		selectWindow("Grayscale PSR Signal");
		run("Set Scale...", "distance=1 known=" + pixelWidth + " unit=" + scaleUnit); // Restoring scale
		saveAs("Tiff", PSRImgDir + "Grayscale_PSR_Signal_" + imgList[imgSubsetIndexArray[k]]);
		run("Measure");
		selectWindow("TotalSignal");
		run("Invert");
		roiManager("select", 0);
		run("Set Scale...", "distance=1 known=" + pixelWidth + " unit=" + scaleUnit); // Restoring scale
		saveAs("Tiff", totalTissueDir + "Total_Tissue_" + imgList[imgSubsetIndexArray[k]]);
		run("Measure");
		// Intermediate export of data if requested
		if (intermediateExport) {
			saveAs("Results", dataDir + "IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
		}
 		close("*");
 		run("Collect Garbage");
 		roiManager("reset");
 	}
 // Below is the continuation of the progress bar for loop initiated above
 	print(progBarTitle, "\\Close");
}

// Fetching data and time for unique export
getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
// Padding and offsetting month
month = IJ.pad(month + 1, 2);
dayOfMonth = IJ.pad(dayOfMonth, 2);
hour = IJ.pad(hour, 2);
minute = IJ.pad(minute, 2);
second = IJ.pad(second, 2);

// Exporting data table
saveAs("Results", dataDir + year + month + dayOfMonth + "_" + hour + "-" + minute + "-" + second + "_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
// Deleting exported intermediate data table
if (intermediateExport) {
	File.delete(dataDir + "IntermediateExport_PSR_GrayscaleSignal_and_TotalTissueSignal.CSV");
	// File deletion command typically prints boolean completion in log, closing log
	if (isOpen("Log")) {
		selectWindow("Log");
		run("Close");
	}
}

// Creating and exporting table for parameters used
if (autoTrace) {
	strAutoTrace = "True";
} else {
	strAutoTrace = "False";
}
Table.create("Parameters");
Table.set("Canvas processing", 0, canvasProcessingApproach);
Table.set("Auto trace", 0, strAutoTrace);
Table.set("Tissue detection Gaussian Sigma", 0, tissueGaussianSigma);
Table.set("PSR hue bandpass", 0, "" + hueLower + "-" + hueUpper);
Table.set("PSR saturation bandpass", 0, "" + satLower + "-" + satUpper);
Table.set("PSR brightness bandpass", 0, "" + briLower + "-" + briUpper);
Table.set("Artifact green bandpass", 0, "" + artifactLower + "-" + artifactUpper);
Table.set("Artifact detection Gaussian Sigma", 0, artifactGaussianSigma);
Table.set("Artifact minimum size (post-blur)", 0, artifactMinSize);
Table.save(dataDir + year + month + dayOfMonth + "_" + hour + "-" + minute + "-" + second + "_PSR_Macro_Parameters.CSV");
Table.update;
close("Parameters");

// Elapsed time and time per image
timeStamp2 = getTime();
elapsedTimeMS = timeStamp2 - timeStamp1;
	if (elapsedTimeMS < 60000) {
		elapsedTime = d2s(elapsedTimeMS / 1000, 0);
		timeUnit = "sec";
	}
	if (elapsedTimeMS > 60000) {
		elapsedTime = d2s(elapsedTimeMS / 60000, 1);
		timeUnit = "min";
	}
	if (elapsedTimeMS > 3600000) {
		elapsedTime = d2s(elapsedTimeMS / 3600000, 2);
		timeUnit = "hr";
	}
	
timePerImage = d2s((elapsedTimeMS / 1000) / imgSubsetIndexArray.length, 2);
waitForUser("Done!", imgSubsetIndexArray.length + " images have been processed, and the output images and results have been saved to the indicated directory at:\n\n" +
	outputDir + "\n Elapsed time = " + elapsedTime + " " + timeUnit + "\n On average, " + timePerImage + " sec/image");
