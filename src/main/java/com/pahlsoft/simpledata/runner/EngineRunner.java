package com.pahlsoft.simpledata.runner;

import com.pahlsoft.simpledata.model.Configuration;
import com.pahlsoft.simpledata.model.Workload;
import com.pahlsoft.simpledata.engine.WorkloadGeneratorEngine;
import com.pahlsoft.simpledata.threader.WorkloadGeneratorEngineThreader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.Constructor;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.util.Iterator;
import java.util.Objects;

public class EngineRunner {
    static Logger log = LoggerFactory.getLogger(EngineRunner.class);

    private static Configuration configuration;

    public static void main(String[] args) {
       validateArguments(args);
        loadConfig(args[0]);
        Workload workload = null;
        Iterator iterator = configuration.getWorkloads().iterator();
        try {

            while (iterator.hasNext()) {
                workload = (Workload) iterator.next();
                WorkloadGeneratorEngineThreader.runEngine(workload.getWorkloadThreads(), new WorkloadGeneratorEngine(configuration,workload));
            }

            System.out.println("Workloads Started.");

        } catch (Exception e) {
            log.error(e.getMessage());
        }

    }

    private static void loadConfig(String args) {
            try {
                Yaml yaml = new Yaml(new Constructor(Configuration.class));
                InputStream inputStream = new FileInputStream(new File(args));
                configuration = yaml.load(inputStream);
                validateConfig(configuration);

            } catch (NullPointerException npe) {
                log.error("Missing critical configuration check config file : " +  args);
                System.out.println("Unable to Load YML model file: missing configs: " + args);
                System.exit(1);
            } catch (Exception e) {
                if (log.isDebugEnabled()) {
                    log.error(e.getMessage());
                } else {
                    log.error("General configuration error. Check config file : " +  args);
                    System.out.println("Unable to Load YML model file: Check config file: " + args);
                    System.exit(1);
                }
            }

        log.info("Configuration Loaded");
        System.out.println("Configuration Loaded.");
    }

    private static void validateConfig(Configuration configuration) throws IllegalAccessException {
        if (configuration.emptyFields()) {
            throw new NullPointerException();  // HERE: DUDE YOU LEFT OFF FIGURING THIS OUT!!!
        }
    }

    private static void validateArguments(String[] args) {
        if (args.length !=1 ) {
            System.out.println("Error - Improper Usage, try: sample-data-generator-*.jar your_config_file.yml ");
            log.error("Error - Improper Usage, try: sample-data-generator-*.jar your_config_file.yml ");
            System.exit(1);
        }
    }
}
